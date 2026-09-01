import http from "node:http";
import { createHash, timingSafeEqual } from "node:crypto";
import { readFileSync } from "node:fs";

const port = Number(process.env.PORT ?? 8787);
const workoutGeneratorModel = process.env.OPENAI_MODEL ?? "gpt-4.1";
const photoImportModel = process.env.OPENAI_PHOTO_IMPORT_MODEL ?? "gpt-4.1-mini";
const transcriptionModel = process.env.OPENAI_TRANSCRIBE_MODEL ?? "gpt-4o-mini-transcribe";
const apiKey = process.env.OPENAI_API_KEY ?? "";

// --- Deployment hardening (all optional; local dev behavior is unchanged when unset) ---

function envInt(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

// Shared app token. When set, every /api/* request must carry it in the
// x-app-token header. It gates abuse of a deployed backend; it is not a
// per-user credential. Unset = open (local dev).
const appToken = (process.env.APP_TOKEN ?? "").trim();

// Sliding-window rate limit per token+IP. 0 disables the limiter.
const rateLimitMax = envInt("RATE_LIMIT_MAX", 40);
const rateLimitWindowMs = Math.max(1, envInt("RATE_LIMIT_WINDOW_SEC", 600)) * 1000;

// Max accepted POST body in bytes. Sized so the cap never rejects a payload
// OpenAI itself would accept: photo import sends up to ~5MB PNG (~6.7MB as
// base64) and voice import sends uncompressed WAV whose upstream limit is a
// 25MB decoded file (~33.4MB as base64 JSON).
const maxBodyBytes = Math.max(1, envInt("MAX_BODY_BYTES", 36_000_000));

function timingSafeTokenMatch(provided, expected) {
  // Hash both sides so lengths always match; comparison stays constant-time.
  const providedDigest = createHash("sha256").update(provided).digest();
  const expectedDigest = createHash("sha256").update(expected).digest();
  return timingSafeEqual(providedDigest, expectedDigest);
}

// key -> array of request timestamps (ms) inside the current window.
const rateLimitWindows = new Map();
const rateLimitMaxKeys = 10_000;

function rateLimitKey(request) {
  const forwarded = request.headers["x-forwarded-for"];
  const forwardedIp = typeof forwarded === "string" ? forwarded.split(",")[0].trim() : "";
  const ip = forwardedIp || request.socket.remoteAddress || "unknown";
  const rawToken = request.headers["x-app-token"];
  const tokenPart = typeof rawToken === "string" && rawToken
    ? createHash("sha256").update(rawToken).digest("hex").slice(0, 16)
    : "anon";
  return `${tokenPart}|${ip}`;
}

function checkRateLimit(key) {
  if (rateLimitMax === 0) return { allowed: true, retryAfter: 0 };

  const now = Date.now();
  const cutoff = now - rateLimitWindowMs;
  const timestamps = (rateLimitWindows.get(key) ?? []).filter((ts) => ts > cutoff);

  if (timestamps.length >= rateLimitMax) {
    rateLimitWindows.set(key, timestamps);
    const retryAfter = Math.max(1, Math.ceil((timestamps[0] + rateLimitWindowMs - now) / 1000));
    return { allowed: false, retryAfter };
  }

  timestamps.push(now);

  // Memory bound: hard cap on tracked keys (evict oldest insertion first).
  if (!rateLimitWindows.has(key) && rateLimitWindows.size >= rateLimitMaxKeys) {
    const oldestKey = rateLimitWindows.keys().next().value;
    rateLimitWindows.delete(oldestKey);
  }

  rateLimitWindows.set(key, timestamps);
  return { allowed: true, retryAfter: 0 };
}

// Periodic sweep so idle keys do not accumulate between requests.
setInterval(() => {
  const cutoff = Date.now() - rateLimitWindowMs;
  for (const [key, timestamps] of rateLimitWindows) {
    const alive = timestamps.filter((ts) => ts > cutoff);
    if (alive.length === 0) {
      rateLimitWindows.delete(key);
    } else if (alive.length !== timestamps.length) {
      rateLimitWindows.set(key, alive);
    }
  }
}, 60_000).unref();

// --- Exercise catalog grounding ---------------------------------------------
// Routine-producing endpoints used to emit exercise names blind, so the model
// free-styled ("Standing OHP", invented flourishes) and drafts landed in the
// app as unresolvable custom noise. backend/exercise-catalog.json (generated
// by harness/gen-exercise-catalog.py from the bundled dataset + alias table,
// drift-checked by harness/checks.sh) carries every library exercise name;
// each routine-producing call now receives a request-relevant subset and must
// copy names from it verbatim. Inventing a name is the sanctioned LAST resort,
// flagged per exercise via catalogMatch.

const exerciseCatalog = (() => {
  try {
    return JSON.parse(readFileSync(new URL("./exercise-catalog.json", import.meta.url), "utf8"));
  } catch (error) {
    console.warn(`exercise-catalog.json missing or invalid — catalog grounding disabled. (${error?.message ?? error})`);
    return [];
  }
})();

const catalogNameSet = new Set(exerciseCatalog.map((entry) => entry.name.toLowerCase()));

const catalogByGroup = new Map();
for (const entry of exerciseCatalog) {
  const group = catalogByGroup.get(entry.muscleGroup) ?? [];
  group.push(entry);
  catalogByGroup.set(entry.muscleGroup, group);
}

// Muscle-group hints scanned out of request text. Over-inclusion is cheap
// (round-robin fill keeps the subset capped); under-inclusion is what hurts,
// and the always-included staple backbone covers every group regardless.
const muscleGroupHintPatterns = [
  [/\b(chest|pecs?|bench|push[ -]?ups?|fly|flyes?|flies|dips?|press day)\b/, ["Chest"]],
  [/\bpush(es|ing)?\b/, ["Chest", "Shoulders", "Arms"]],
  [/\b(back|rows?|lats?|pull[ -]?downs?|pull[ -]?ups?|chin[ -]?ups?|shrugs?)\b/, ["Back"]],
  [/\bpull(s|ing)?\b/, ["Back", "Arms"]],
  [/\b(shoulders?|delts?|ohp|overhead|military|lateral raises?|face pulls?)\b/, ["Shoulders"]],
  [/\b(arms?|biceps?|triceps?|curls?|skull ?crushers?|push[ -]?downs?|extensions?|forearms?|grip)\b/, ["Arms"]],
  [/\b(legs?|quads?|hamstrings?|hammies|glutes?|calf|calves|squats?|lunges?|dead ?lifts?|rdls?|sldl|hip thrusts?|hinge|lower body)\b/, ["Legs"]],
  [/\b(core|abs?|abdominals?|obliques?|planks?|six[ -]?pack)\b/, ["Core"]],
  [/\b(cardio|conditioning|hiit|runs?|running|sprints?|bikes?|cycling|rowing|rower|treadmill|jump rope|stairs?)\b/, ["Cardio"]],
  [/\b(full[ -]?body|total[ -]?body|whole body|crossfit|circuits?|complex(es)?|cleans?|snatch(es)?|jerks?|thrusters?|burpees?)\b/, ["Full Body"]],
  [/\b(mobility|stretch(es|ing)?|warm[ -]?up|cool[ -]?down|yoga|foam roll(ing)?|recovery)\b/, ["Mobility"]],
  [/\b(carry|carries|farmer'?s?|sleds?|strongman|battle ropes?|band(s|ed)?)\b/, ["Other"]]
];

// User equipment-preference strings -> catalog equipment enum values.
const equipmentAliasPairs = [
  ["barbell", "Barbell"],
  ["dumbbell", "Dumbbell"], ["db", "Dumbbell"],
  ["machine", "Machine"],
  ["cable", "Cable"],
  ["bodyweight", "Bodyweight"], ["body weight", "Bodyweight"], ["calisthenic", "Bodyweight"], ["no equipment", "Bodyweight"],
  ["kettlebell", "Kettlebell"], ["kb", "Kettlebell"],
  ["band", "Band"],
  ["medicine ball", "Medicine Ball"], ["med ball", "Medicine Ball"]
];

function preferredEquipmentSet(preferences) {
  const set = new Set();
  for (const raw of Array.isArray(preferences?.preferredEquipment) ? preferences.preferredEquipment : []) {
    const lowered = String(raw).toLowerCase();
    for (const [needle, equipment] of equipmentAliasPairs) {
      if (lowered.includes(needle)) set.add(equipment);
    }
  }
  return set;
}

function hintedMuscleGroups(text) {
  const lowered = ` ${String(text ?? "").toLowerCase()} `;
  const hinted = [];
  for (const [pattern, groups] of muscleGroupHintPatterns) {
    if (!pattern.test(lowered)) continue;
    for (const group of groups) {
      if (!hinted.includes(group)) hinted.push(group);
    }
  }
  return hinted;
}

// Names-only budget: ~240 names ≈ 1.2–1.5k prompt tokens.
const catalogSubsetMaxNames = 240;

// Select the request-relevant slice of the catalog: the staple backbone always
// (the classics, every muscle group), then the hinted muscle groups expanded
// round-robin — entries matching the user's preferred equipment first — until
// the name cap. `fallbackText` (memory focus, conversation) is scanned only
// when `primaryText` yields no muscle-group hints; no hints at all expands
// every group evenly.
function selectCatalogSubset(primaryText, preferences, fallbackText = "") {
  if (exerciseCatalog.length === 0) return [];

  let hinted = hintedMuscleGroups(primaryText);
  if (hinted.length === 0) hinted = hintedMuscleGroups(fallbackText);
  const groups = hinted.length > 0 ? hinted : [...catalogByGroup.keys()];
  const preferredEquipment = preferredEquipmentSet(preferences);

  const chosen = new Map(); // lowercased name -> entry

  for (const entry of exerciseCatalog) {
    if (entry.staple) chosen.set(entry.name.toLowerCase(), entry);
  }

  const passFilters = preferredEquipment.size > 0
    ? [(entry) => preferredEquipment.has(entry.equipment) || entry.equipment === "Bodyweight", () => true]
    : [() => true];

  for (const passFilter of passFilters) {
    if (chosen.size >= catalogSubsetMaxNames) break;
    const queues = groups.map((group) =>
      (catalogByGroup.get(group) ?? []).filter(
        (entry) => passFilter(entry) && !chosen.has(entry.name.toLowerCase())
      )
    );
    let added = true;
    while (added && chosen.size < catalogSubsetMaxNames) {
      added = false;
      for (const queue of queues) {
        if (chosen.size >= catalogSubsetMaxNames) break;
        const entry = queue.shift();
        if (entry) {
          chosen.set(entry.name.toLowerCase(), entry);
          added = true;
        }
      }
    }
  }

  return [...chosen.values()];
}

function formatCatalogSection(subset) {
  if (subset.length === 0) return "";

  const namesByGroup = new Map();
  for (const entry of subset) {
    const names = namesByGroup.get(entry.muscleGroup) ?? [];
    names.push(entry.name);
    namesByGroup.set(entry.muscleGroup, names);
  }

  const lines = [...namesByGroup.keys()]
    .sort()
    .map((group) => `${group}: ${namesByGroup.get(group).join(" | ")}`);

  return ["", "EXERCISE LIBRARY (canonical names, grouped by muscle group):", ...lines].join("\n");
}

function catalogGroundingBlock(primaryText, preferences, fallbackText = "") {
  return formatCatalogSection(selectCatalogSubset(primaryText, preferences, fallbackText));
}

// Muscle-group focus terms from the user-memory digest — subset-selection
// fallback when the request text itself names no muscle groups.
function memoryFocusText(memory) {
  if (!memory) return "";
  const weekly = Array.isArray(memory.weeklySummaries) ? memory.weeklySummaries : [];
  return weekly.flatMap((week) => (Array.isArray(week.focus) ? week.focus : [])).join(" ");
}

function routineExerciseNamesText(routine) {
  if (!routine || !Array.isArray(routine.exercises)) return "";
  return routine.exercises.map((exercise) => String(exercise?.name ?? "")).join(" ");
}

// One line per model call so grounding cost stays observable in dev logs.
function logModelUsage(label, payload) {
  const usage = payload?.usage;
  if (usage) {
    console.log(`[usage] ${label} input=${usage.input_tokens ?? "?"} output=${usage.output_tokens ?? "?"}`);
  }
}

const workoutSchema = {
  type: "object",
  additionalProperties: false,
  required: ["title", "summary", "rationale", "routineNotes", "exercises"],
  properties: {
    title: { type: "string" },
    summary: {
      type: "string",
      description: "One concrete sentence saying what this workout is — split, equipment, focus, or constraint. Add a second sentence ONLY if it carries genuinely distinct information. Never restate the goal in different words and never add generic benefit-speak like maximizing volume, efficiently, or keeps things effective."
    },
    rationale: { type: "string" },
    routineNotes: {
      type: "array",
      items: { type: "string" }
    },
    exercises: {
      type: "array",
      minItems: 1,
      maxItems: 12,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "sets", "reps", "notes", "reasoning", "tip", "catalogMatch"],
        properties: {
          name: { type: "string" },
          catalogMatch: {
            type: "boolean",
            description: "true when name is copied verbatim from the provided EXERCISE LIBRARY list; false only when the movement has no library entry and a custom or standard non-library name was used."
          },
          sets: { type: "integer", minimum: 1, maximum: 10 },
          reps: { type: "string" },
          notes: { type: "string" },
          reasoning: {
            type: "string",
            description: "Why this exercise is in this plan — its role, one short sentence, at most 15 words."
          },
          tip: {
            type: "string",
            description: "One practical execution or setup tip for THIS exercise in THIS workout — form, setup, tempo, or rest. At most 12 words."
          }
        }
      }
    }
  }
};

const workoutRevisionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["reply", "action", "changeSummary", "routine"],
  properties: {
    reply: { type: "string" },
    action: {
      type: "string",
      enum: ["reply_only", "suggestion", "created_draft", "updated_draft"]
    },
    changeSummary: {
      anyOf: [
        { type: "string" },
        { type: "null" }
      ]
    },
    routine: {
      anyOf: [
        workoutSchema,
        { type: "null" }
      ]
    }
  }
};

// M4 adaptation loop: constrained next-session nudge after a post-workout
// check-in. Same exercises, same order, names echoed verbatim — only
// load/rep/set-count targets move. Never a replan.
const workoutNudgeSchema = {
  type: "object",
  additionalProperties: false,
  required: ["overallNote", "exercises"],
  properties: {
    overallNote: {
      type: "string",
      description: "One short plain sentence describing the session-level adjustment. No filler."
    },
    exercises: {
      type: "array",
      minItems: 1,
      maxItems: 20,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "suggestedWeightText", "repText", "setCount", "whyNote"],
        properties: {
          name: {
            type: "string",
            description: "Exercise name copied VERBATIM from the request routine. Never a new exercise."
          },
          suggestedWeightText: {
            anyOf: [{ type: "string" }, { type: "null" }],
            description: "Next-session load target as short text with unit, matching how the user logs (e.g. 145 lb, bodyweight). Null when unchanged."
          },
          repText: {
            anyOf: [{ type: "string" }, { type: "null" }],
            description: "Next-session rep target (e.g. 8 or 8-10). Null when unchanged."
          },
          setCount: {
            anyOf: [{ type: "integer", minimum: 1, maximum: 10 }, { type: "null" }],
            description: "Next-session set count. Null when unchanged."
          },
          whyNote: {
            anyOf: [{ type: "string" }, { type: "null" }],
            description: "At most 12 words tying the change to what the user reported or lifted. Null when nothing changed."
          }
        }
      }
    }
  }
};

const exerciseSwapSchema = {
  type: "object",
  additionalProperties: false,
  required: ["suggestions"],
  properties: {
    suggestions: {
      type: "array",
      minItems: 1,
      maxItems: 4,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["exerciseName", "reason", "preserves", "caution"],
        properties: {
          exerciseName: { type: "string" },
          reason: { type: "string" },
          preserves: {
            type: "array",
            items: { type: "string" }
          },
          caution: {
            anyOf: [
              { type: "string" },
              { type: "null" }
            ]
          }
        }
      }
    }
  }
};

const exerciseCoachSchema = {
  type: "object",
  additionalProperties: false,
  required: ["answer", "suggestions"],
  properties: {
    answer: { type: "string" },
    suggestions: {
      type: "array",
      maxItems: 3,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["exerciseName", "reason"],
        properties: {
          exerciseName: { type: "string" },
          reason: { type: "string" }
        }
      }
    }
  }
};

const exerciseFormCuesSchema = {
  type: "object",
  additionalProperties: false,
  required: ["cues"],
  properties: {
    cues: {
      type: "array",
      minItems: 3,
      maxItems: 3,
      items: { type: "string" }
    }
  }
};

const exerciseSimpleExplanationSchema = {
  type: "object",
  additionalProperties: false,
  required: ["explanation"],
  properties: {
    explanation: { type: "string" }
  }
};

const routineSimpleExplanationSchema = {
  type: "object",
  additionalProperties: false,
  required: ["explanation"],
  properties: {
    explanation: { type: "string" }
  }
};

const photoWorkoutSchema = {
  type: "object",
  additionalProperties: false,
  required: ["rawText", "days"],
  properties: {
    rawText: { type: "string" },
    days: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "sourceHeading", "notes", "exercises"],
        properties: {
          name: { type: "string" },
          sourceHeading: {
            anyOf: [
              { type: "string" },
              { type: "null" }
            ]
          },
          notes: {
            type: "array",
            items: { type: "string" }
          },
          exercises: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["sourceText", "exerciseText", "setCount", "repText", "notes", "restSeconds", "intensityNotes"],
              properties: {
                sourceText: { type: "string" },
                exerciseText: { type: "string" },
                setCount: {
                  anyOf: [
                    { type: "integer", minimum: 1, maximum: 20 },
                    { type: "null" }
                  ]
                },
                repText: {
                  anyOf: [
                    { type: "string" },
                    { type: "null" }
                  ]
                },
                notes: {
                  type: "array",
                  items: { type: "string" }
                },
                restSeconds: {
                  anyOf: [
                    { type: "integer", minimum: 0, maximum: 1800 },
                    { type: "null" }
                  ]
                },
                intensityNotes: {
                  type: "array",
                  items: { type: "string" }
                }
              }
            }
          }
        }
      }
    }
  }
};

const photoWorkoutRevisionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["reply", "action", "changeSummary", "extraction"],
  properties: {
    reply: { type: "string" },
    action: {
      type: "string",
      enum: ["reply_only", "suggestion", "created_draft", "updated_draft"]
    },
    changeSummary: {
      anyOf: [
        { type: "string" },
        { type: "null" }
      ]
    },
    extraction: {
      anyOf: [
        photoWorkoutSchema,
        { type: "null" }
      ]
    }
  }
};

const voiceWorkoutParseSchema = {
  type: "object",
  additionalProperties: false,
  required: ["exercises", "skipped"],
  properties: {
    exercises: {
      type: "array",
      maxItems: 20,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["sourceText", "name", "setCount", "repText", "confidence"],
        properties: {
          sourceText: { type: "string" },
          name: { type: "string" },
          setCount: {
            anyOf: [
              { type: "integer", minimum: 1, maximum: 20 },
              { type: "null" }
            ]
          },
          repText: {
            anyOf: [
              { type: "string" },
              { type: "null" }
            ]
          },
          confidence: {
            type: "string",
            enum: ["high", "low"]
          }
        }
      }
    },
    skipped: {
      type: "array",
      maxItems: 12,
      items: { type: "string" }
    }
  }
};

const coachChatSchema = {
  type: "object",
  additionalProperties: false,
  required: ["reply", "action", "changeSummary", "routine", "editedRoutineID"],
  properties: {
    reply: { type: "string" },
    action: {
      type: "string",
      enum: ["reply_only", "suggestion", "created_draft", "updated_draft"]
    },
    changeSummary: {
      anyOf: [
        { type: "string" },
        { type: "null" }
      ]
    },
    routine: {
      anyOf: [
        workoutSchema,
        { type: "null" }
      ]
    },
    editedRoutineID: {
      anyOf: [
        { type: "string" },
        { type: "null" }
      ],
      description: "The exact id of the saved routine this draft modifies, copied verbatim from the saved routine list or the active workout context. null when the draft is brand-new or when no routine is returned."
    }
  }
};

const coachVoiceGuidelines = [
  "Sound like a knowledgeable gym coach talking to a real lifter.",
  "Be confident, practical, and supportive without sounding salesy, robotic, or overexcited.",
  "Use direct gym-specific language such as push, pull, hinge, squat, machine, dumbbell, cable, recovery, and fatigue when relevant.",
  "Keep explanations concise and useful. Prefer one or two tight sentences over long paragraphs.",
  "Explain the training logic in plain English, focusing on time cap, equipment, fatigue, joint comfort, muscle emphasis, exercise order, or simplicity when relevant.",
  "Avoid filler, generic motivation, corporate tone, and vague phrases like optimized for your goals unless you explain what that means.",
  "Do not mention being an AI, a language model, hidden reasoning, or chain-of-thought."
].join(" ");

const preferenceInstructions = [
  "You may receive a saved user preference profile.",
  "Use those preferences when they help, especially for equipment, disliked exercises, limitations, preferred style, and default time limits.",
  "Treat the user's current request or imported content as the highest priority if it conflicts with the saved profile.",
  "Do not mention the saved profile explicitly unless it helps explain a coaching choice."
].join(" ");

const userMemoryInstructions = [
  "You may receive a USER MEMORY digest summarizing the user's real logged training history.",
  "It is tiered: the most recent sessions are detailed, weeks two through thirteen are weekly summaries, and everything older is monthly one-liners plus durable lifetime facts such as all-time PRs, pain history, and consistency.",
  "Treat it as ground truth about what the user actually did, and prefer newer information when tiers disagree.",
  "Use it to personalize: base loads and progressions on recent numbers, respect recovery after heavy recent volume, reference PRs accurately, and never program movements that clash with a reported pain or limitation without adjusting for it.",
  "Do not recite the memory back to the user; use it the way a coach who knows their history would."
].join(" ");

const catalogGroundingInstructions = [
  "The request includes an EXERCISE LIBRARY section listing canonical exercise names from the app's own database.",
  "Whenever a movement you program exists in that list under any name, you MUST copy the library name EXACTLY as written, character for character.",
  "Translate slang, nicknames, abbreviations, and typos to the library name they mean: OHP is the barbell overhead press entry, pec deck is the machine chest fly entry, SLDL is the stiff-leg deadlift entry, skullcrushers is the skull crusher entry.",
  "NEVER invent a novel or creative exercise name, and never add flourishes, prefixes, or rebrands to a library name.",
  "If the user explicitly asks to include their own custom-named exercise, use the user's name for it verbatim.",
  "Only as a last resort, when the user asks for a movement that genuinely has no entry in the library list, name it by its most standard plain gym name.",
  "Set catalogMatch to true when the exercise name is copied verbatim from the EXERCISE LIBRARY list, and false only when you used a custom or non-library name.",
  "Never mention the library list to the user."
].join(" ");

const routineFieldGuidelines = [
  "Write the summary as one concrete sentence a beginner can read at a glance. Add a second sentence only when it carries genuinely distinct information, such as a constraint, equipment note, or scheduling detail.",
  "Never pad the summary with filler that restates the goal or with generic benefit-speak such as maximizing volume, efficiently, keeps things effective, or optimized. If the second sentence only rephrases the first, drop it.",
  "For each exercise, fill reasoning with one short sentence, at most 15 words, naming its role in this plan, such as main press for chest, balancing pull for the back, or easy-recovery finisher.",
  "reasoning must be specific to this plan, never generic filler like great exercise or builds muscle.",
  "For each exercise, fill tip with one practical how-to line for this workout, at most 12 words, covering form, setup, tempo, or rest, such as Rest about 2 minutes between sets.",
  "Anchor form and setup tips to a landmark the lifter can check mid-set, such as Lower until upper arms are parallel to the floor or Keep the bar over mid-foot, never vague effort words like go deep, stay tight, or use good form.",
  "When the tip warns against a mistake, name its consequence if it fits the word budget, such as Don't let knees cave in, it stresses the knee.",
  "Put workout-level advice such as warm-up, rest periods, equipment setup, or pacing into the tip of the exercise where it matters most, never into routineNotes.",
  "Leave routineNotes empty unless one short reminder truly applies to the whole session and fits no single exercise."
].join(" ");

const workoutGeneratorInstructions = [
  "You write practical gym routines for a workout tracking app.",
  "Match the user's requested split, equipment, time cap, and goal as closely as possible.",
  catalogGroundingInstructions,
  "The name field must contain only the exercise name, never sets, reps, numbering, or prescription text.",
  "Keep the plan efficient and realistic for the requested duration.",
  "Include a short rationale that explains why this workout structure fits the user's request.",
  "The rationale should read like a concise coach note, not hidden reasoning or a step-by-step chain of thought.",
  "The summary should read like a practical overview of the session, not generic app copy.",
  routineFieldGuidelines,
  coachVoiceGuidelines,
  preferenceInstructions,
  userMemoryInstructions,
  "Use working sets only.",
  "Make rep targets concise, such as 5-8, 8-10, 10-15, or 30 sec.",
  "Only add exercise notes when they are genuinely useful.",
  "Do not include markdown or commentary outside the JSON schema."
].join(" ");

const supplementaryWorkoutInstructions = [
  "You write small supplementary workout blocks for a gym tracking app.",
  "These are short add-ons such as warm-ups, finishers, recovery blocks, burnout sets, or quick focused accessories.",
  "Keep the block compact, practical, and easy to layer onto another workout.",
  "Prefer 2 to 5 exercises unless the user clearly asks for something else.",
  "Keep the title specific to the add-on block.",
  catalogGroundingInstructions,
  "The name field must contain only the exercise name, never sets, reps, numbering, or prescription text.",
  "Use the summary to explain what the add-on is for in plain English.",
  "Use the rationale like a concise coach note about why this small block fits.",
  routineFieldGuidelines,
  coachVoiceGuidelines,
  preferenceInstructions,
  "Use working sets only unless the user explicitly asks for a warm-up series.",
  "Make rep targets concise, such as 8-12, 12-20, 30 sec, or 60 sec.",
  "Only add exercise notes when they are actually helpful.",
  "Do not include markdown or commentary outside the JSON schema."
].join(" ");

const photoImportInstructions = [
  "You extract workout plans from images for a gym tracking app.",
  "Read screenshots, typed plans, routine sheets, and handwritten workout notes when legible.",
  "Return only data grounded in the image. Do not invent exercises, sets, reps, or notes.",
  "Preserve visible shorthand such as DB, BB, RDL, OHP, AMRAP, and warm-up notes in sourceText.",
  "Use rawText for the best plain-text reconstruction of the workout content in reading order.",
  "Group exercises into days when the image clearly shows day names or headings.",
  "If no clear day heading is visible, place the exercises in a single day named Imported Workout.",
  "When a field is unclear, leave it null or empty instead of guessing.",
  preferenceInstructions,
  "Ignore unrelated decorative UI text that is clearly not part of the workout plan.",
  "Do not include markdown or commentary outside the JSON schema."
].join(" ");

const voiceWorkoutParseInstructions = [
  "You extract exercise names from a spoken workout transcript for a gym tracking app.",
  "The transcript is casual speech, often full of filler and hype. Your only job is to find the phrases that plausibly name a physical exercise and list them in spoken order.",
  "Extract a phrase ONLY when it plausibly names a real physical exercise or movement, such as bench press, dumbbell curl, plank, lat pulldown, or box jump.",
  "IGNORE filler such as um, uh, like, you know, okay, so, I mean.",
  "IGNORE hype and buzzwords such as crush it, beast mode, pump, pump city, superset vibes, let's go, no excuses.",
  "IGNORE greetings, sign-offs, self-talk, and commentary about how the workout will feel.",
  "IGNORE goals, adjectives, and vague intentions such as something heavy, for chest, maybe abs, a little cardio. A bare body part or muscle group is NOT an exercise name.",
  "IGNORE set and rep chatter that is not attached to a specific exercise.",
  "NEVER invent, substitute, or guess an exercise to represent a non-exercise phrase. If a phrase is not plausibly an exercise name, it must not appear in exercises.",
  "Put the notable non-exercise phrases you deliberately left out into skipped, shortened to a few words each. Pure filler like um or okay does not belong in either list.",
  "For each extracted exercise, sourceText is the exact words heard and name is the cleaned exercise name with no sets, reps, numbering, or prescription text.",
  "The request may include an EXERCISE LIBRARY section listing canonical exercise names from the app's database. When an extracted exercise clearly and unambiguously refers to a library entry, output that library name EXACTLY as written as name, keeping sourceText as the words heard. When no library entry clearly matches, or the spoken words are an abbreviation or nickname you are not certain about, keep the cleaned spoken name unchanged instead of guessing a library entry. The library list NEVER adds exercises: extract only movements the speaker actually said.",
  "When the speaker attaches sets or reps to an exercise, such as three sets of ten, fill that exercise's setCount and repText. Otherwise leave them null.",
  "Set confidence to high when the phrase clearly and unambiguously names an exercise. Set confidence to low when it is garbled, partial, or you are unsure it really names an exercise.",
  "If the transcript names no exercises, return an empty exercises list. Never pad it.",
  "Do not include markdown or commentary outside the JSON schema."
].join(" ");

const workoutRevisionInstructions = [
  "You revise structured gym routines for a workout tracking app.",
  "You will receive the user's current routine and a follow-up edit request.",
  "You may also receive earlier conversation context. Use it to stay consistent with the user's preferences.",
  "Act like a chat-first coach. Some user messages are only questions, some are suggestions, and some are direct requests to change the draft.",
  "Choose action reply_only when the user mainly wants explanation or reassurance and the routine should stay exactly the same.",
  "Choose action suggestion when you want to recommend a change but are not actually changing the routine yet.",
  "Choose action updated_draft only when the user clearly wants the routine changed right now.",
  "Apply the user's requested changes while keeping the routine practical and coherent.",
  "Keep the workout style, equipment constraints, and overall intent unless the user asks to change them.",
  "Prefer swapping exercises over rewriting everything when the request is small.",
  catalogGroundingInstructions,
  "Exercises kept unchanged from the current routine keep their existing names; catalogMatch for them reflects whether that name appears in the EXERCISE LIBRARY list.",
  "The name field must contain only the exercise name, never sets, reps, numbering, or prescription text.",
  "Update the rationale so it briefly explains why the revised version fits the user's request.",
  "The rationale should stay concise and user-facing, not hidden reasoning or chain-of-thought.",
  routineFieldGuidelines,
  "Write reply as a short coach-style response that explains what changed and why.",
  "When action is updated_draft, fill changeSummary with one short plain-English sentence describing the change.",
  "When action is reply_only or suggestion, set routine to null and changeSummary to null.",
  coachVoiceGuidelines,
  preferenceInstructions,
  userMemoryInstructions,
  "Only return JSON matching the schema."
].join(" ");

const workoutNudgeInstructions = [
  "You make small next-session adjustments to one saved workout routine after a post-workout check-in.",
  "You receive the routine's exercises with their current set counts and the user's most recent numbers, the fresh check-in, and their training history digest.",
  "Return the SAME exercises in the SAME order, exactly one entry per exercise, each name copied VERBATIM from the request. Never add, drop, merge, rename, or reorder exercises. This is a nudge, not a replan.",
  "Only load, rep targets, and set counts may move.",
  "Check-in too easy: modest progression — roughly 2.5 to 5 percent more load, or one more set where load is not the lever. Round to practical gym increments.",
  "Check-in too hard: back off — roughly 5 to 10 percent less load, or one fewer set. Never increase anything.",
  "Check-in about right: tiny or no change. Leaving every field null for an exercise is a good answer when its numbers are working.",
  "Base every target on the recent numbers provided. When an exercise has no recent numbers, leave its fields null rather than inventing a load.",
  "suggestedWeightText is short text with a unit, matching how the user logs (145 lb, bodyweight). repText is a plain rep target like 8 or 8-10.",
  "Each whyNote is at most 12 words, grounded in what the user reported or lifted. Plain language, no jargon.",
  "overallNote is one short plain sentence describing the session-level adjustment.",
  userMemoryInstructions,
  "Only return JSON matching the schema."
].join(" ");

const importRevisionInstructions = [
  "You revise structured workout drafts for a gym tracking app.",
  "You will receive the current routine draft plus a user edit request.",
  "You may also receive earlier conversation context. Use it to stay consistent with the user's preferences.",
  "Act like a chat-first coach. Some user messages are only questions, some are suggestions, and some are direct requests to change the draft.",
  "Choose action reply_only when the user mainly wants explanation or reassurance and the draft should stay exactly the same.",
  "Choose action suggestion when you want to recommend a change but are not actually changing the draft yet.",
  "Choose action updated_draft only when the user clearly wants the draft changed right now.",
  "Return the revised routine in the provided schema with day names, exercise lines, sets, reps, notes, rest, and intensity notes when they are known.",
  "Preserve the existing structure when the request is small, but make the requested changes clearly.",
  "Do not invent extra certainty. If a field is unclear after the revision, leave it null or empty.",
  "Write reply as a short coach-style response that explains what changed and why.",
  "When action is updated_draft, fill changeSummary with one short plain-English sentence describing the change.",
  "When action is reply_only or suggestion, set extraction to null and changeSummary to null.",
  coachVoiceGuidelines,
  preferenceInstructions,
  "rawText should be a clean plain-text reconstruction of the revised routine.",
  "Only return JSON matching the schema."
].join(" ");

const coachChatInstructions = [
  "You are Lokt, a chat-first gym coach inside a workout app.",
  "The user may be planning a new workout, editing a current draft, or asking for help during an active workout.",
  "Act like a real coach texting back: concise, practical, specific, and useful.",
  "Do not force every message into a workout change.",
  "You also receive the user's saved routine library: each entry has an id, a name, and its exercise list.",
  "When the user references an existing workout by name or description, match it against the saved routine library. Tolerate partial and fuzzy references: my push day matches a longer push-day title, legs matches a leg day routine.",
  "If exactly one saved routine plausibly matches, work with that one. If several plausibly match, ask which one they mean instead of guessing, using action reply_only.",
  "Never tell the user a workout does not exist while the saved routine list is non-empty. If nothing matches what they described, say which routines you do see and ask which they mean.",
  "When you edit a saved routine, base the draft on that routine's ACTUAL exercises: apply only the requested change and preserve every other exercise, its order, and its sets and reps.",
  "Choose action reply_only when the user mainly wants an answer, reassurance, or explanation.",
  "Choose action suggestion when you want to recommend a change but should not edit the draft yet.",
  "Choose action created_draft when the user clearly wants a brand-new structured workout that is not based on a saved routine or the current draft.",
  "Choose action updated_draft when the user clearly wants the current routine or a specific saved routine changed right now.",
  "Set editedRoutineID to the exact id of the saved routine your draft modifies, copied verbatim from the list, or the active workout's routine id when you are modifying that. Set editedRoutineID to null whenever the draft is brand-new or you return no routine.",
  "If the user is in active workout context, prefer practical coaching help unless they clearly ask for the rest of the workout to be rebuilt.",
  "When action is created_draft or updated_draft, return a complete routine in the schema and write a short changeSummary.",
  "When action is reply_only or suggestion, set routine to null and changeSummary to null.",
  "If a routine is returned, keep the name field to exercise names only, never sets, reps, numbering, or prescription text.",
  catalogGroundingInstructions,
  "When you edit a saved routine, its existing exercises keep their exact names; catalogMatch for them reflects whether that name appears in the EXERCISE LIBRARY list.",
  routineFieldGuidelines,
  coachVoiceGuidelines,
  preferenceInstructions,
  userMemoryInstructions,
  "Only return JSON matching the schema."
].join(" ");

const exerciseSwapInstructions = [
  "You suggest exercise replacements for a gym tracking app.",
  "You will receive the current exercise, the user's reason for swapping it, and a shortlist of candidate replacements.",
  "Pick replacements that keep the workout's purpose as intact as possible.",
  "Favor similar movement pattern, muscle emphasis, and practical equipment fit.",
  "If the user asks for shoulder-friendly, easier, dumbbell, or home-gym options, prioritize those constraints clearly.",
  coachVoiceGuidelines,
  "reason should be a short coach-style explanation of why the replacement fits.",
  "preserves should be short phrases like upper chest focus, horizontal press pattern, or lower setup time.",
  "caution should be null unless there is one quick tradeoff worth mentioning.",
  "Only choose names from the provided candidate list.",
  "Only return JSON matching the schema."
].join(" ");

const exerciseCoachInstructions = [
  "You answer exercise-specific coaching questions for a gym tracking app.",
  "You will receive the current exercise, the user's question, and a shortlist of related exercises you may use if a swap or alternative would help.",
  "Answer like a concise strength coach, not a generic assistant.",
  "Keep the answer short, direct, and practical.",
  "Focus on what the movement trains, why someone would use it, setup simplicity, joint comfort, or substitute logic when relevant.",
  coachVoiceGuidelines,
  "Only include suggestions when a substitution, easier option, or alternative genuinely helps.",
  "If you include suggestions, only choose names from the provided candidate list.",
  "Each suggestion reason should be one short coach-style sentence.",
  "Do not include markdown or extra commentary outside the JSON schema."
].join(" ");

const exerciseFormCuesInstructions = [
  "You write ultra-brief form cues for one gym exercise in a workout tracking app.",
  "Return exactly three cues.",
  "Cue 1: setup — stance, foot position, grip, or body position.",
  "Cue 2: the single most important thing to do while performing the rep.",
  "Cue 3: the most common mistake, phrased as what to avoid.",
  "Anchor cues 1 and 2 to a landmark the lifter can see or feel mid-set, such as bar over mid-foot, thighs parallel to the floor, or elbows under the wrists, never vague words like deep, tight, or good form.",
  "In cue 3, pair the visible mistake with the problem it causes, such as Don't let knees cave in, it stresses the knee.",
  "Each cue is one short sentence, at most 12 words.",
  "Use plain language a beginner understands. No anatomy jargon.",
  "Do not include markdown, numbering, or anything outside the JSON schema."
].join(" ");

const exerciseSimpleExplanationInstructions = [
  "You explain one gym exercise to someone who has never lifted weights.",
  "Write like you are talking to a friend. Plain, everyday words only.",
  "Never use gym or anatomy jargon such as hypertrophy, scapular retraction, RPE, eccentric, tempo, or posterior chain.",
  "Cover: what the exercise is, what part of the body it works in everyday terms, why it is worth doing, and how it should feel when done right.",
  "Go a little deeper than a one-line summary, but stay under 120 words.",
  "Use short sentences in one or two flowing paragraphs. No markdown, no lists.",
  "Do not include anything outside the JSON schema."
].join(" ");

const routineSimpleExplanationInstructions = [
  "You explain a full workout routine to a friend who has never lifted weights.",
  "Write like you are talking to that friend. Plain, everyday words only.",
  "Never use gym or anatomy jargon such as hypertrophy, superset, compound, accessory, RPE, eccentric, tempo, or posterior chain.",
  "First say in one or two sentences what this workout as a whole does for the body.",
  "Then walk through the exercises in order, one short line each, saying in everyday terms what it works and why it is in the plan.",
  "Mention how it should roughly feel, like tiring but doable, when that helps.",
  "Go deeper than a one-line overview, but stay under 160 words.",
  "Use short sentences in a few flowing paragraphs. No markdown, no lists, no headings.",
  "Do not include anything outside the JSON schema."
].join(" ");

const server = http.createServer(async (request, response) => {
  if (request.method === "OPTIONS") {
    sendJson(response, 204, {});
    return;
  }

  if (request.method === "GET" && request.url === "/health") {
    sendJson(response, 200, {
      ok: true,
      configured: Boolean(apiKey),
      models: {
        workoutGenerator: workoutGeneratorModel,
        photoImport: photoImportModel,
        transcription: transcriptionModel
      }
    });
    return;
  }

  if (request.url?.startsWith("/api/")) {
    if (appToken) {
      const providedToken = request.headers["x-app-token"];
      if (typeof providedToken !== "string" || providedToken === "" || !timingSafeTokenMatch(providedToken, appToken)) {
        sendJson(response, 401, {
          error: "Missing or invalid app token."
        });
        return;
      }
    }

    const rateLimit = checkRateLimit(rateLimitKey(request));
    if (!rateLimit.allowed) {
      response.setHeader("Retry-After", String(rateLimit.retryAfter));
      sendJson(response, 429, {
        error: "Too many requests. Try again shortly.",
        retryAfter: rateLimit.retryAfter
      });
      return;
    }
  }

  if (request.method === "POST" && request.url === "/api/ai/workout-generator") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
      const preferences = normalizePreferences(body?.preferences);
      const memory = normalizeUserMemory(body?.memory);

      if (prompt.length < 8) {
        sendJson(response, 400, {
          error: "Prompt must be at least 8 characters long."
        });
        return;
      }

      const routineResult = await generateWorkoutRoutine(prompt, preferences, memory);

      sendJson(response, 200, {
        routine: routineResult.routine,
        requestId: routineResult.requestId,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to generate the workout."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/workout-addon") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
      const preferences = normalizePreferences(body?.preferences);

      if (prompt.length < 8) {
        sendJson(response, 400, {
          error: "Prompt must be at least 8 characters long."
        });
        return;
      }

      const routineResult = await generateSupplementaryWorkout(prompt, preferences);

      sendJson(response, 200, {
        routine: routineResult.routine,
        requestId: routineResult.requestId,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to generate the add-on workout."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/workout-generator/revise") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const editPrompt = typeof body?.editPrompt === "string" ? body.editPrompt.trim() : "";
      const currentRoutine = body?.currentRoutine ?? null;
      const conversation = normalizeConversation(body?.conversation);
      const preferences = normalizePreferences(body?.preferences);
      const memory = normalizeUserMemory(body?.memory);

      if (editPrompt.length < 8) {
        sendJson(response, 400, {
          error: "Revision prompt must be at least 8 characters long."
        });
        return;
      }

      if (!currentRoutine || typeof currentRoutine !== "object") {
        sendJson(response, 400, {
          error: "Current routine data is required."
        });
        return;
      }

      const routineResult = await reviseWorkoutRoutine({ editPrompt, currentRoutine, conversation, preferences, memory });

      sendJson(response, 200, {
        routine: routineResult.routine,
        reply: routineResult.reply,
        action: routineResult.action,
        changeSummary: routineResult.changeSummary,
        requestId: routineResult.requestId,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to revise the workout."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/workout-nudge") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const routine = normalizeNudgeRoutine(body?.routine);
      const checkIn = normalizeNudgeCheckIn(body?.checkIn);
      const preferences = normalizePreferences(body?.preferences);
      const memory = normalizeUserMemory(body?.memory);

      if (!routine) {
        sendJson(response, 400, {
          error: "Routine with a name and 1-20 named exercises is required."
        });
        return;
      }

      if (!checkIn) {
        sendJson(response, 400, {
          error: "Check-in with outcome too_easy, about_right, or too_hard is required."
        });
        return;
      }

      // Safety branch (spine §6), enforced server-side as defense in depth:
      // a pain-flagged check-in gets a real conversation with the coach,
      // never a silent numeric nudge — even if a client asks anyway.
      if (checkIn.hadPain || checkIn.painNote || checkIn.painExercise) {
        sendJson(response, 422, {
          error: "Pain check-ins are not auto-adjusted. Route the user to the coach instead.",
          safety: "pain_check_in"
        });
        return;
      }

      const nudgeResult = await nudgeWorkoutRoutine({ routine, checkIn, preferences, memory });

      sendJson(response, 200, {
        nudge: nudgeResult.nudge,
        requestId: nudgeResult.requestId,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to build the workout nudge."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/workout-generator/explain") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const routine = normalizeRoutineExplainInput(body?.routine);

      if (!routine) {
        sendJson(response, 400, {
          error: "Routine data with a title and at least one exercise is required."
        });
        return;
      }

      const explainResult = await explainWorkoutRoutine(routine);

      sendJson(response, 200, {
        ...explainResult,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to explain the workout."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/photo-to-workout/extract") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const imageBase64 = typeof body?.imageBase64 === "string" ? body.imageBase64 : "";
      const fileName = typeof body?.fileName === "string" && body.fileName.trim() ? body.fileName.trim() : "photo-workout-import.png";
      const mimeType = typeof body?.mimeType === "string" && body.mimeType.trim() ? body.mimeType.trim() : "image/png";
      const preferences = normalizePreferences(body?.preferences);

      if (!imageBase64) {
        sendJson(response, 400, {
          error: "Image data is required."
        });
        return;
      }

      const extractionResult = await extractWorkoutFromImage({
        imageBase64,
        fileName,
        mimeType,
        preferences
      });

      sendJson(response, 200, {
        extraction: extractionResult.extraction,
        requestId: extractionResult.requestId,
        model: photoImportModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to extract workout data from the image."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/workout-import/revise") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const editPrompt = typeof body?.editPrompt === "string" ? body.editPrompt.trim() : "";
      const currentDraft = body?.currentDraft ?? null;
      const conversation = normalizeConversation(body?.conversation);
      const preferences = normalizePreferences(body?.preferences);

      if (editPrompt.length < 8) {
        sendJson(response, 400, {
          error: "Revision prompt must be at least 8 characters long."
        });
        return;
      }

      if (!currentDraft || typeof currentDraft !== "object") {
        sendJson(response, 400, {
          error: "Current workout draft is required."
        });
        return;
      }

      const revisionResult = await reviseImportedWorkout({ editPrompt, currentDraft, conversation, preferences });

      sendJson(response, 200, {
        extraction: revisionResult.extraction,
        reply: revisionResult.reply,
        action: revisionResult.action,
        changeSummary: revisionResult.changeSummary,
        requestId: revisionResult.requestId,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to revise the imported workout."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/coach/chat") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const message = typeof body?.message === "string" ? body.message.trim() : "";
      const conversation = normalizeConversation(body?.conversation);
      const currentRoutine = body?.currentRoutine ?? null;
      const context = normalizeCoachContext(body?.context);
      const savedRoutines = normalizeSavedRoutines(body?.savedRoutines);
      const preferences = normalizePreferences(body?.preferences);
      const memory = normalizeUserMemory(body?.memory);

      if (message.length < 4) {
        sendJson(response, 400, {
          error: "Coach message must be at least 4 characters long."
        });
        return;
      }

      const coachResult = await chatWithCoach({
        message,
        conversation,
        currentRoutine,
        context,
        savedRoutines,
        preferences,
        memory
      });

      sendJson(response, 200, {
        reply: coachResult.reply,
        action: coachResult.action,
        changeSummary: coachResult.changeSummary,
        routine: coachResult.routine,
        editedRoutineID: coachResult.editedRoutineID,
        requestId: coachResult.requestId,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to chat with the coach."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/exercise-swap/suggest") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const currentExercise = body?.currentExercise ?? null;
      const reason = typeof body?.reason === "string" ? body.reason.trim() : "";
      const candidates = Array.isArray(body?.candidates) ? body.candidates : [];

      if (!currentExercise || typeof currentExercise !== "object") {
        sendJson(response, 400, {
          error: "Current exercise data is required."
        });
        return;
      }

      if (reason.length < 4) {
        sendJson(response, 400, {
          error: "Swap reason must be at least 4 characters long."
        });
        return;
      }

      if (candidates.length === 0) {
        sendJson(response, 400, {
          error: "At least one swap candidate is required."
        });
        return;
      }

      const swapResult = await suggestExerciseSwaps({ currentExercise, reason, candidates });

      sendJson(response, 200, {
        suggestions: swapResult.suggestions,
        requestId: swapResult.requestId,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to suggest exercise swaps."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/exercise-coach/answer") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const currentExercise = body?.currentExercise ?? null;
      const question = typeof body?.question === "string" ? body.question.trim() : "";
      const candidates = Array.isArray(body?.candidates) ? body.candidates : [];

      if (!currentExercise || typeof currentExercise !== "object") {
        sendJson(response, 400, {
          error: "Current exercise data is required."
        });
        return;
      }

      if (question.length < 4) {
        sendJson(response, 400, {
          error: "Question must be at least 4 characters long."
        });
        return;
      }

      const coachResult = await answerExerciseQuestion({ currentExercise, question, candidates });

      sendJson(response, 200, {
        answer: coachResult.answer,
        suggestions: coachResult.suggestions,
        requestId: coachResult.requestId,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to answer the exercise question."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/exercise-coach/explain") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const exercise = body?.exercise ?? null;
      const mode = typeof body?.mode === "string" ? body.mode.trim().toLowerCase() : "";

      if (!exercise || typeof exercise !== "object" || typeof exercise.name !== "string" || !exercise.name.trim()) {
        sendJson(response, 400, {
          error: "Exercise data with a name is required."
        });
        return;
      }

      if (mode !== "cues" && mode !== "simple") {
        sendJson(response, 400, {
          error: "Mode must be \"cues\" or \"simple\"."
        });
        return;
      }

      const explainResult = await explainExercise({ exercise, mode });

      sendJson(response, 200, {
        ...explainResult,
        model: workoutGeneratorModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to explain the exercise."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/voice-to-workout/transcribe") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const audioBase64 = typeof body?.audioBase64 === "string" ? body.audioBase64 : "";
      const fileName = typeof body?.fileName === "string" && body.fileName.trim() ? body.fileName.trim() : "voice-workout.m4a";
      const mimeType = typeof body?.mimeType === "string" && body.mimeType.trim() ? body.mimeType.trim() : "audio/m4a";

      if (!audioBase64) {
        sendJson(response, 400, {
          error: "Audio data is required."
        });
        return;
      }

      const transcription = await transcribeVoiceRecording({
        audioBase64,
        fileName,
        mimeType
      });

      sendJson(response, 200, transcription);
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to transcribe the recording."
      });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/api/ai/voice-to-workout/parse") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request, response);
      const transcript = typeof body?.transcript === "string" ? body.transcript.trim() : "";

      if (transcript.length < 3) {
        sendJson(response, 400, {
          error: "Transcript is required."
        });
        return;
      }

      const parseResult = await parseVoiceWorkoutTranscript(transcript.slice(0, 20_000));

      sendJson(response, 200, {
        parse: parseResult.parse,
        requestId: parseResult.requestId,
        model: photoImportModel
      });
    } catch (error) {
      sendJson(response, 502, {
        error: error instanceof Error ? error.message : "Failed to parse the transcript into exercises."
      });
    }
    return;
  }

  sendJson(response, 404, {
    error: "Route not found."
  });
});

server.listen(port, () => {
  const authStatus = appToken ? "app-token auth ON" : "auth OFF (APP_TOKEN unset — local dev)";
  const limitStatus = rateLimitMax === 0
    ? "rate limit OFF"
    : `rate limit ${rateLimitMax}/${Math.round(rateLimitWindowMs / 1000)}s`;
  console.log(`Lokt AI backend listening on port ${port} — ${authStatus}, ${limitStatus}`);
});

async function generateWorkoutRoutine(prompt, preferences, memory = null) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: workoutGeneratorInstructions,
      input: formatPromptWithPreferences(prompt, preferences, memory)
        + catalogGroundingBlock(prompt, preferences, memoryFocusText(memory)),
      text: {
        format: {
          type: "json_schema",
          name: "workout_routine",
          strict: true,
          schema: workoutSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI request failed.");
  }

  logModelUsage("workout-generator", payload);

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured JSON output.");
  }

  let routine;

  try {
    routine = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed JSON.");
  }

  return {
    requestId: payload.id ?? null,
    routine: sanitizeRoutine(routine)
  };
}

async function generateSupplementaryWorkout(prompt, preferences) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: supplementaryWorkoutInstructions,
      input: formatPromptWithPreferences(prompt, preferences)
        + catalogGroundingBlock(prompt, preferences),
      text: {
        format: {
          type: "json_schema",
          name: "supplementary_workout_block",
          strict: true,
          schema: workoutSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI supplementary workout request failed.");
  }

  logModelUsage("workout-addon", payload);

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured add-on JSON.");
  }

  let routine;

  try {
    routine = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed add-on JSON.");
  }

  return {
    requestId: payload.id ?? null,
    routine: sanitizeRoutine(routine)
  };
}

async function reviseWorkoutRoutine({ editPrompt, currentRoutine, conversation, preferences, memory = null }) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: workoutRevisionInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Current routine JSON:",
                JSON.stringify(currentRoutine, null, 2),
                "",
                "Saved user preferences:",
                formatPreferences(preferences),
                "",
                "USER MEMORY:",
                formatUserMemory(memory),
                "",
                "Earlier conversation:",
                formatConversation(conversation),
                "",
                "User edit request:",
                editPrompt,
                catalogGroundingBlock(
                  `${editPrompt} ${routineExerciseNamesText(currentRoutine)}`,
                  preferences,
                  memoryFocusText(memory)
                )
              ].join("\n")
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "workout_routine_revision",
          strict: true,
          schema: workoutRevisionSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI revision request failed.");
  }

  logModelUsage("workout-generator/revise", payload);

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured revision JSON.");
  }

  let revision;

  try {
    revision = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed revision JSON.");
  }

  return {
    requestId: payload.id ?? null,
    action: sanitizeCoachAction(revision?.action),
    reply: sanitizeReply(revision?.reply),
    changeSummary: sanitizeChangeSummary(revision?.changeSummary, revision?.action),
    routine: sanitizeOptionalRoutine(revision?.routine, revision?.action)
  };
}

async function nudgeWorkoutRoutine({ routine, checkIn, preferences, memory = null }) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: workoutNudgeInstructions,
      input: [
        `Routine being adjusted: "${routine.name}"`,
        formatNudgeRoutine(routine),
        "",
        "Post-workout check-in:",
        formatNudgeCheckIn(checkIn),
        "",
        "Saved user preferences:",
        formatPreferences(preferences),
        "",
        "USER MEMORY:",
        formatUserMemory(memory)
      ].join("\n"),
      text: {
        format: {
          type: "json_schema",
          name: "workout_nudge",
          strict: true,
          schema: workoutNudgeSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI nudge request failed.");
  }

  logModelUsage("workout-nudge", payload);

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured nudge JSON.");
  }

  let nudge;

  try {
    nudge = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed nudge JSON.");
  }

  return {
    requestId: payload.id ?? null,
    nudge: sanitizeWorkoutNudge(nudge, routine)
  };
}

function formatNudgeRoutine(routine) {
  return routine.exercises
    .map((exercise) => {
      const target = [
        exercise.sets !== null ? `${exercise.sets} sets` : null,
        exercise.repText ? `${exercise.repText} reps` : null
      ].filter(Boolean).join(" x ");
      const last = [
        exercise.lastWeightText,
        exercise.lastRepText ? `x ${exercise.lastRepText}` : null
      ].filter(Boolean).join(" ");
      const facts = [
        target || null,
        last ? `last logged: ${last}` : "no recent numbers"
      ].filter(Boolean).join(" | ");
      return `- ${exercise.name}${facts ? ` | ${facts}` : ""}`;
    })
    .join("\n");
}

function formatNudgeCheckIn(checkIn) {
  const outcomeText = {
    too_easy: "too easy",
    about_right: "about right",
    too_hard: "too hard"
  }[checkIn.overall] ?? checkIn.overall;
  return `The session overall felt: ${outcomeText}. No pain reported.`;
}

async function extractWorkoutFromImage({ imageBase64, mimeType, preferences }) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: photoImportModel,
      store: false,
      instructions: photoImportInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Extract the workout plan from this image into the schema. Preserve ambiguous phrases in sourceText rather than guessing.",
                "",
                "Saved user preferences:",
                formatPreferences(preferences)
              ].join("\n")
            },
            {
              type: "input_image",
              image_url: `data:${mimeType};base64,${imageBase64}`
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "photo_workout_extraction",
          strict: true,
          schema: photoWorkoutSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI image extraction failed.");
  }

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured extraction output.");
  }

  let extraction;

  try {
    extraction = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed extraction JSON.");
  }

  return {
    requestId: payload.id ?? null,
    extraction: sanitizePhotoWorkoutExtraction(extraction)
  };
}

async function reviseImportedWorkout({ editPrompt, currentDraft, conversation, preferences }) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: importRevisionInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Current workout draft JSON:",
                JSON.stringify(currentDraft, null, 2),
                "",
                "Saved user preferences:",
                formatPreferences(preferences),
                "",
                "Earlier conversation:",
                formatConversation(conversation),
                "",
                "User edit request:",
                editPrompt
              ].join("\n")
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "workout_import_revision",
          strict: true,
          schema: photoWorkoutRevisionSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI import revision failed.");
  }

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured import revision JSON.");
  }

  let revision;

  try {
    revision = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed import revision JSON.");
  }

  return {
    requestId: payload.id ?? null,
    action: sanitizeCoachAction(revision?.action),
    reply: sanitizeReply(revision?.reply),
    changeSummary: sanitizeChangeSummary(revision?.changeSummary, revision?.action),
    extraction: sanitizeOptionalPhotoWorkoutExtraction(revision?.extraction, revision?.action)
  };
}

async function chatWithCoach({ message, conversation, currentRoutine, context, savedRoutines, preferences, memory = null }) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: coachChatInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Coach context:",
                formatCoachContext(context),
                "",
                "Current routine JSON:",
                currentRoutine ? JSON.stringify(currentRoutine, null, 2) : "None.",
                "",
                "Saved routine library:",
                formatSavedRoutines(savedRoutines),
                "",
                "Saved user preferences:",
                formatPreferences(preferences),
                "",
                "USER MEMORY:",
                formatUserMemory(memory),
                "",
                "Earlier conversation:",
                formatConversation(conversation),
                "",
                "Latest user message:",
                message,
                catalogGroundingBlock(
                  [
                    message,
                    routineExerciseNamesText(currentRoutine),
                    ...(Array.isArray(context?.activeWorkout?.exercises) ? context.activeWorkout.exercises : [])
                  ].join(" "),
                  preferences,
                  [
                    ...(Array.isArray(conversation) ? conversation.slice(-6).map((item) => item.text) : []),
                    memoryFocusText(memory)
                  ].join(" ")
                )
              ].join("\n")
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "coach_chat_response",
          strict: true,
          schema: coachChatSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI coach chat request failed.");
  }

  logModelUsage("coach/chat", payload);

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured coach JSON.");
  }

  let coachResponse;

  try {
    coachResponse = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed coach JSON.");
  }

  const sanitizedRoutine = sanitizeOptionalRoutine(coachResponse?.routine, coachResponse?.action);

  return {
    requestId: payload.id ?? null,
    action: sanitizeCoachAction(coachResponse?.action),
    reply: sanitizeReply(coachResponse?.reply),
    changeSummary: sanitizeChangeSummary(coachResponse?.changeSummary, coachResponse?.action),
    routine: sanitizedRoutine,
    editedRoutineID: sanitizedRoutine
      ? sanitizeEditedRoutineID(coachResponse?.editedRoutineID, savedRoutines, context)
      : null
  };
}

async function suggestExerciseSwaps({ currentExercise, reason, candidates }) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: exerciseSwapInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Current exercise JSON:",
                JSON.stringify(currentExercise, null, 2),
                "",
                "Swap reason:",
                reason,
                "",
                "Candidate replacements JSON:",
                JSON.stringify(candidates, null, 2)
              ].join("\n")
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "exercise_swap_suggestions",
          strict: true,
          schema: exerciseSwapSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI exercise swap request failed.");
  }

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured exercise swap JSON.");
  }

  let responseBody;

  try {
    responseBody = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed exercise swap JSON.");
  }

  return {
    requestId: payload.id ?? null,
    suggestions: sanitizeExerciseSwapSuggestions(responseBody?.suggestions, candidates)
  };
}

async function answerExerciseQuestion({ currentExercise, question, candidates }) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: exerciseCoachInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Current exercise JSON:",
                JSON.stringify(currentExercise, null, 2),
                "",
                "User question:",
                question,
                "",
                "Related exercise candidates JSON:",
                JSON.stringify(candidates, null, 2)
              ].join("\n")
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "exercise_coach_answer",
          strict: true,
          schema: exerciseCoachSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI exercise coach request failed.");
  }

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured exercise coach JSON.");
  }

  let responseBody;

  try {
    responseBody = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed exercise coach JSON.");
  }

  return {
    requestId: payload.id ?? null,
    answer: sanitizeCoachAnswer(responseBody?.answer),
    suggestions: sanitizeExerciseCoachSuggestions(responseBody?.suggestions, candidates)
  };
}

async function explainExercise({ exercise, mode }) {
  const isCuesMode = mode === "cues";

  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: isCuesMode ? exerciseFormCuesInstructions : exerciseSimpleExplanationInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Exercise JSON:",
                JSON.stringify(exercise, null, 2)
              ].join("\n")
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: isCuesMode ? "exercise_form_cues" : "exercise_simple_explanation",
          strict: true,
          schema: isCuesMode ? exerciseFormCuesSchema : exerciseSimpleExplanationSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI exercise explain request failed.");
  }

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured exercise explanation JSON.");
  }

  let responseBody;

  try {
    responseBody = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed exercise explanation JSON.");
  }

  if (isCuesMode) {
    const cues = Array.isArray(responseBody?.cues)
      ? responseBody.cues.map((cue) => String(cue).trim()).filter(Boolean).slice(0, 3)
      : [];

    if (cues.length < 3) {
      throw new Error("The form cues came back incomplete.");
    }

    return {
      requestId: payload.id ?? null,
      cues
    };
  }

  const explanation = typeof responseBody?.explanation === "string" ? responseBody.explanation.trim() : "";

  if (!explanation) {
    throw new Error("The simple explanation came back empty.");
  }

  return {
    requestId: payload.id ?? null,
    explanation
  };
}

function normalizeRoutineExplainInput(routine) {
  if (!routine || typeof routine !== "object") {
    return null;
  }

  const title = typeof routine.title === "string" ? routine.title.trim() : "";
  const summary = typeof routine.summary === "string" ? routine.summary.trim() : "";

  const exercises = Array.isArray(routine.exercises)
    ? routine.exercises
        .map((exercise) => ({
          name: String(exercise?.name ?? "").trim(),
          sets: Number.isFinite(Number(exercise?.sets)) ? clampNumber(Number(exercise.sets), 1, 10) : null,
          reps: String(exercise?.reps ?? "").trim(),
          reasoning: String(exercise?.reasoning ?? "").trim()
        }))
        .filter((exercise) => exercise.name)
        .slice(0, 12)
    : [];

  if (!title || exercises.length === 0) {
    return null;
  }

  return { title, summary, exercises };
}

async function explainWorkoutRoutine(routine) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: workoutGeneratorModel,
      store: false,
      instructions: routineSimpleExplanationInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Workout routine JSON:",
                JSON.stringify(routine, null, 2)
              ].join("\n")
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "routine_simple_explanation",
          strict: true,
          schema: routineSimpleExplanationSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI routine explain request failed.");
  }

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured routine explanation JSON.");
  }

  let responseBody;

  try {
    responseBody = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed routine explanation JSON.");
  }

  const explanation = typeof responseBody?.explanation === "string" ? responseBody.explanation.trim() : "";

  if (!explanation) {
    throw new Error("The routine explanation came back empty.");
  }

  return {
    requestId: payload.id ?? null,
    explanation
  };
}

async function transcribeVoiceRecording({ audioBase64, fileName, mimeType }) {
  const audioBuffer = Buffer.from(audioBase64, "base64");
  const audioBlob = new Blob([audioBuffer], { type: mimeType });
  const formData = new FormData();

  formData.append("file", audioBlob, fileName);
  formData.append("model", transcriptionModel);
  formData.append("response_format", "json");

  const apiResponse = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`
    },
    body: formData
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI transcription failed.");
  }

  const transcript = typeof payload?.text === "string" ? payload.text.trim() : "";
  if (!transcript) {
    throw new Error("OpenAI returned an empty transcript.");
  }

  return {
    transcript,
    model: transcriptionModel,
    durationSeconds: Number.isFinite(payload?.duration) ? payload.duration : null
  };
}

async function parseVoiceWorkoutTranscript(transcript) {
  const apiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: photoImportModel,
      store: false,
      instructions: voiceWorkoutParseInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Spoken workout transcript:",
                transcript,
                catalogGroundingBlock(transcript, null)
              ].join("\n")
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "voice_workout_parse",
          strict: true,
          schema: voiceWorkoutParseSchema
        }
      }
    })
  });

  const payload = await apiResponse.json();

  if (!apiResponse.ok) {
    throw new Error(payload?.error?.message ?? "OpenAI transcript parsing failed.");
  }

  logModelUsage("voice-to-workout/parse", payload);

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI returned a response without structured parse output.");
  }

  let parsed;

  try {
    parsed = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI returned malformed parse JSON.");
  }

  return {
    requestId: payload.id ?? null,
    parse: sanitizeVoiceWorkoutParse(parsed)
  };
}

function sanitizeVoiceWorkoutParse(parsed) {
  const exercises = Array.isArray(parsed?.exercises)
    ? parsed.exercises
        .map((exercise) => {
          const name = String(exercise?.name ?? "").trim().slice(0, 80);
          const sourceText = String(exercise?.sourceText ?? "").trim().slice(0, 160);

          return {
            sourceText: sourceText || name,
            name: name || sourceText,
            setCount: Number.isFinite(exercise?.setCount) ? clampNumber(exercise.setCount, 1, 20) : null,
            repText: typeof exercise?.repText === "string" && exercise.repText.trim()
              ? exercise.repText.trim().slice(0, 24)
              : null,
            confidence: exercise?.confidence === "high" ? "high" : "low"
          };
        })
        .filter((exercise) => exercise.name)
        .slice(0, 20)
    : [];

  const skipped = Array.isArray(parsed?.skipped)
    ? parsed.skipped
        .map((phrase) => String(phrase).trim().slice(0, 80))
        .filter(Boolean)
        .slice(0, 12)
    : [];

  return { exercises, skipped };
}

function extractOutputText(payload) {
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) {
    return payload.output_text;
  }

  const output = Array.isArray(payload?.output) ? payload.output : [];

  for (const item of output) {
    const content = Array.isArray(item?.content) ? item.content : [];

    for (const chunk of content) {
      if (typeof chunk?.text === "string" && chunk.text.trim()) {
        return chunk.text;
      }
    }
  }

  return "";
}

function normalizeConversation(value) {
  const items = Array.isArray(value) ? value : [];

  return items
    .map((item) => ({
      role: typeof item?.role === "string" ? item.role.trim().toLowerCase() : "",
      text: typeof item?.text === "string" ? item.text.trim() : ""
    }))
    .filter((item) => (item.role === "user" || item.role === "assistant") && item.text);
}

function normalizeCoachContext(value) {
  const kind = typeof value?.kind === "string" ? value.kind.trim().toLowerCase() : "planning";
  const activeWorkout = value?.activeWorkout ?? null;

  return {
    kind: kind === "draft_editing" || kind === "active_workout" ? kind : "planning",
    activeWorkout: activeWorkout && typeof activeWorkout === "object"
      ? {
          routineID: typeof activeWorkout.routineID === "string" ? activeWorkout.routineID.trim().slice(0, 64) : "",
          routineName: typeof activeWorkout.routineName === "string" ? activeWorkout.routineName.trim() : "",
          exercises: Array.isArray(activeWorkout.exercises)
            ? activeWorkout.exercises.map((item) => String(item).trim()).filter(Boolean).slice(0, 20)
            : [],
          nextExercise: typeof activeWorkout.nextExercise === "string" ? activeWorkout.nextExercise.trim() : "",
          // M4 safety branch: post-workout check-in summary (pain flag /
          // repeated too-hard) riding along so the coach addresses it first.
          checkInNote: typeof activeWorkout.checkInNote === "string"
            ? activeWorkout.checkInNote.trim().slice(0, 240)
            : ""
        }
      : null
  };
}

function normalizeSavedRoutines(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .slice(0, 20)
    .map((routine) => {
      const id = typeof routine?.id === "string" ? routine.id.trim().slice(0, 64) : "";
      const name = typeof routine?.name === "string" ? routine.name.trim().slice(0, 120) : "";
      if (!id || !name) {
        return null;
      }

      const exercises = (Array.isArray(routine?.exercises) ? routine.exercises : [])
        .slice(0, 20)
        .map((exercise) => {
          const exerciseName = typeof exercise?.name === "string" ? exercise.name.trim().slice(0, 80) : "";
          if (!exerciseName) {
            return null;
          }

          const sets = Number.isInteger(exercise?.sets) && exercise.sets >= 1 && exercise.sets <= 10
            ? exercise.sets
            : null;
          const reps = typeof exercise?.reps === "string" && exercise.reps.trim()
            ? exercise.reps.trim().slice(0, 24)
            : null;

          return { name: exerciseName, sets, reps };
        })
        .filter(Boolean);

      return { id, name, exercises };
    })
    .filter(Boolean);
}

function formatSavedRoutines(savedRoutines) {
  if (!Array.isArray(savedRoutines) || savedRoutines.length === 0) {
    return "None.";
  }

  return savedRoutines
    .map((routine) => {
      const exercises = routine.exercises
        .map((exercise) => {
          const prescription = [
            exercise.sets ? `${exercise.sets} sets` : null,
            exercise.reps ? `${exercise.reps} reps` : null
          ].filter(Boolean).join(" x ");
          return prescription ? `${exercise.name} (${prescription})` : exercise.name;
        })
        .join(", ");
      return `- id ${routine.id} | "${routine.name}": ${exercises || "no exercises listed"}`;
    })
    .join("\n");
}

// M4 nudge request: one routine snapshot with per-exercise current targets
// and most recent logged numbers. Length-clamped like every other input.
function normalizeNudgeRoutine(value) {
  const name = typeof value?.name === "string" ? value.name.trim().slice(0, 120) : "";

  const exercises = (Array.isArray(value?.exercises) ? value.exercises : [])
    .slice(0, 20)
    .map((exercise) => {
      const exerciseName = typeof exercise?.name === "string" ? exercise.name.trim().slice(0, 80) : "";
      if (!exerciseName) {
        return null;
      }

      const textOrNull = (input, maxLength) =>
        typeof input === "string" && input.trim() ? input.trim().slice(0, maxLength) : null;

      return {
        name: exerciseName,
        sets: Number.isInteger(exercise?.sets) && exercise.sets >= 1 && exercise.sets <= 10
          ? exercise.sets
          : null,
        repText: textOrNull(exercise?.repText, 24),
        lastWeightText: textOrNull(exercise?.lastWeightText, 24),
        lastRepText: textOrNull(exercise?.lastRepText, 24)
      };
    })
    .filter(Boolean);

  if (!name || exercises.length === 0) {
    return null;
  }

  return { name, exercises };
}

function normalizeNudgeCheckIn(value) {
  const validOutcomes = new Set(["too_easy", "about_right", "too_hard"]);
  const overall = typeof value?.overall === "string" ? value.overall.trim().toLowerCase() : "";

  if (!validOutcomes.has(overall)) {
    return null;
  }

  const textOrNull = (input, maxLength) =>
    typeof input === "string" && input.trim() ? input.trim().slice(0, maxLength) : null;

  return {
    overall,
    hadPain: value?.hadPain === true,
    painNote: textOrNull(value?.painNote, 160),
    painExercise: textOrNull(value?.painExercise, 80)
  };
}

function sanitizeEditedRoutineID(editedRoutineID, savedRoutines, context) {
  const cleaned = typeof editedRoutineID === "string" ? editedRoutineID.trim() : "";
  if (!cleaned) {
    return null;
  }

  const knownIDs = (Array.isArray(savedRoutines) ? savedRoutines : []).map((routine) => routine.id);
  if (context?.activeWorkout?.routineID) {
    knownIDs.push(context.activeWorkout.routineID);
  }

  const match = knownIDs.find((id) => id.toLowerCase() === cleaned.toLowerCase());
  return match ?? null;
}

function normalizePreferences(value) {
  const preferredEquipment = Array.isArray(value?.preferredEquipment)
    ? value.preferredEquipment.map((item) => String(item).trim()).filter(Boolean).slice(0, 10)
    : [];
  const dislikedExercises = Array.isArray(value?.dislikedExercises)
    ? value.dislikedExercises.map((item) => String(item).trim()).filter(Boolean).slice(0, 12)
    : [];
  const primaryGoal = typeof value?.primaryGoal === "string" ? value.primaryGoal.trim() : "";
  const limitations = typeof value?.limitations === "string" ? value.limitations.trim() : "";
  const trainingStyle = typeof value?.trainingStyle === "string" ? value.trainingStyle.trim() : "";
  const defaultTimeLimitMinutes = Number.isFinite(value?.defaultTimeLimitMinutes)
    ? Math.max(5, Math.min(240, Number(value.defaultTimeLimitMinutes)))
    : null;

  return {
    preferredEquipment,
    dislikedExercises,
    primaryGoal,
    limitations,
    trainingStyle,
    defaultTimeLimitMinutes
  };
}

function formatPreferences(preferences) {
  const lines = [];

  if (Array.isArray(preferences?.preferredEquipment) && preferences.preferredEquipment.length > 0) {
    lines.push(`Preferred equipment: ${preferences.preferredEquipment.join(", ")}`);
  }

  if (Array.isArray(preferences?.dislikedExercises) && preferences.dislikedExercises.length > 0) {
    lines.push(`Avoid or minimize: ${preferences.dislikedExercises.join(", ")}`);
  }

  if (preferences?.primaryGoal) {
    lines.push(`Primary goal: ${preferences.primaryGoal}`);
  }

  if (preferences?.limitations) {
    lines.push(`Limitations: ${preferences.limitations}`);
  }

  if (preferences?.trainingStyle) {
    lines.push(`Training style: ${preferences.trainingStyle}`);
  }

  if (Number.isFinite(preferences?.defaultTimeLimitMinutes)) {
    lines.push(`Default time limit: ${preferences.defaultTimeLimitMinutes} minutes`);
  }

  return lines.length > 0 ? lines.join("\n") : "None.";
}

function formatPromptWithPreferences(prompt, preferences, memory = null) {
  const parts = [
    "User request:",
    prompt,
    "",
    "Saved user preferences:",
    formatPreferences(preferences)
  ];

  if (memory) {
    parts.push("", "USER MEMORY:", formatUserMemory(memory));
  }

  return parts.join("\n");
}

// Validates and hard-caps the tiered user-memory digest the app attaches to
// coach chat and generator/revise requests. Everything is length-clamped so a
// hostile or buggy client can never balloon the model context.
function normalizeUserMemory(value) {
  if (!value || typeof value !== "object") {
    return null;
  }

  const text = (input, maxLength) =>
    typeof input === "string" ? input.trim().slice(0, maxLength) : "";
  const count = (input, maxValue) =>
    Number.isFinite(input) ? Math.max(0, Math.min(maxValue, Math.round(Number(input)))) : null;
  const list = (input, maxItems, maxLength) =>
    Array.isArray(input)
      ? input.map((item) => String(item).trim().slice(0, maxLength)).filter(Boolean).slice(0, maxItems)
      : [];

  const recentSessions = (Array.isArray(value.recentSessions) ? value.recentSessions : [])
    .slice(0, 14)
    .map((session) => ({
      date: text(session?.date, 10),
      routine: text(session?.routine, 80),
      sets: count(session?.sets, 200),
      volume: count(session?.volume, 10000000),
      durationMinutes: count(session?.durationMinutes, 1000),
      checkIn: text(session?.checkIn, 24),
      painNote: text(session?.painNote, 160),
      bestSets: list(session?.bestSets, 8, 80),
      prs: list(session?.prs, 6, 90)
    }))
    .filter((session) => session.date && session.routine);

  const weeklySummaries = (Array.isArray(value.weeklySummaries) ? value.weeklySummaries : [])
    .slice(0, 14)
    .map((week) => ({
      weekOf: text(week?.weekOf, 10),
      sessions: count(week?.sessions, 50),
      sets: count(week?.sets, 1000),
      volume: count(week?.volume, 10000000),
      focus: list(week?.focus, 3, 24),
      prs: list(week?.prs, 6, 90),
      introduced: list(week?.introduced, 6, 60),
      dropped: list(week?.dropped, 6, 60)
    }))
    .filter((week) => week.weekOf && week.sessions !== null);

  const rawLifetime = value.lifetime && typeof value.lifetime === "object" ? value.lifetime : null;
  const lifetime = rawLifetime
    ? {
        since: text(rawLifetime.since, 10),
        totalSessions: count(rawLifetime.totalSessions, 100000),
        totalVolume: count(rawLifetime.totalVolume, 2000000000),
        sessionsPerWeek: Number.isFinite(rawLifetime.sessionsPerWeek)
          ? Math.max(0, Math.min(50, Math.round(Number(rawLifetime.sessionsPerWeek) * 10) / 10))
          : null,
        longestStreakWeeks: count(rawLifetime.longestStreakWeeks, 5000),
        allTimePRs: list(rawLifetime.allTimePRs, 15, 100),
        painHistory: list(rawLifetime.painHistory, 10, 170),
        limitations: text(rawLifetime.limitations, 240),
        months: (Array.isArray(rawLifetime.months) ? rawLifetime.months : [])
          .slice(0, 30)
          .map((month) => ({
            month: text(month?.month, 7),
            sessions: count(month?.sessions, 1000),
            volume: count(month?.volume, 100000000),
            focus: list(month?.focus, 3, 24)
          }))
          .filter((month) => month.month && month.sessions !== null)
      }
    : null;

  if (recentSessions.length === 0 && weeklySummaries.length === 0 && !lifetime) {
    return null;
  }

  return { recentSessions, weeklySummaries, lifetime };
}

function formatUserMemory(memory) {
  if (!memory) {
    return "None.";
  }

  const lines = [];

  if (memory.recentSessions.length > 0) {
    lines.push("Recent sessions (newest first, most detailed):");
    for (const session of memory.recentSessions) {
      const facts = [
        session.sets !== null ? `${session.sets} sets` : null,
        session.volume !== null ? `volume ${session.volume}` : null,
        session.durationMinutes !== null ? `${session.durationMinutes} min` : null,
        session.checkIn ? `felt ${session.checkIn}` : null,
        session.painNote ? `pain: ${session.painNote}` : null
      ].filter(Boolean).join(", ");

      let line = `- ${session.date} | ${session.routine}`;
      if (facts) {
        line += ` | ${facts}`;
      }
      if (session.bestSets.length > 0) {
        line += ` | best: ${session.bestSets.join("; ")}`;
      }
      if (session.prs.length > 0) {
        line += ` | ${session.prs.join("; ")}`;
      }
      lines.push(line);
    }
  }

  if (memory.weeklySummaries.length > 0) {
    lines.push("Weekly summaries (2-13 weeks ago):");
    for (const week of memory.weeklySummaries) {
      const facts = [
        `${week.sessions} sessions`,
        week.sets !== null ? `${week.sets} sets` : null,
        week.volume !== null ? `volume ${week.volume}` : null,
        week.focus.length > 0 ? `focus ${week.focus.join("/")}` : null,
        week.prs.length > 0 ? `PRs: ${week.prs.join("; ")}` : null,
        week.introduced.length > 0 ? `introduced ${week.introduced.join(", ")}` : null,
        week.dropped.length > 0 ? `dropped ${week.dropped.join(", ")}` : null
      ].filter(Boolean).join(", ");
      lines.push(`- week of ${week.weekOf}: ${facts}`);
    }
  }

  if (memory.lifetime) {
    const lifetime = memory.lifetime;
    lines.push("Lifetime:");

    const facts = [
      lifetime.since ? `training in app since ${lifetime.since}` : null,
      lifetime.totalSessions !== null ? `${lifetime.totalSessions} total sessions` : null,
      lifetime.totalVolume !== null ? `total volume ${lifetime.totalVolume}` : null,
      lifetime.sessionsPerWeek !== null ? `avg ${lifetime.sessionsPerWeek} sessions/week` : null,
      lifetime.longestStreakWeeks !== null ? `longest streak ${lifetime.longestStreakWeeks} weeks` : null
    ].filter(Boolean).join(", ");
    if (facts) {
      lines.push(`- ${facts}`);
    }
    if (lifetime.allTimePRs.length > 0) {
      lines.push(`- All-time PRs: ${lifetime.allTimePRs.join("; ")}`);
    }
    if (lifetime.painHistory.length > 0) {
      lines.push(`- Pain history: ${lifetime.painHistory.join("; ")}`);
    }
    if (lifetime.limitations) {
      lines.push(`- Standing limitations: ${lifetime.limitations}`);
    }
    for (const month of lifetime.months) {
      const monthFacts = [
        `${month.sessions} sessions`,
        month.volume !== null ? `volume ${month.volume}` : null,
        month.focus.length > 0 ? `focus ${month.focus.join("/")}` : null
      ].filter(Boolean).join(", ");
      lines.push(`- ${month.month}: ${monthFacts}`);
    }
  }

  if (lines.length === 0) {
    return "None.";
  }

  // Final guard well past the app-side cap: never let a crafted payload
  // balloon the context.
  const rendered = lines.join("\n");
  return rendered.length > 9000 ? `${rendered.slice(0, 9000)}\n(truncated)` : rendered;
}

function formatConversation(conversation) {
  if (!Array.isArray(conversation) || conversation.length === 0) {
    return "None.";
  }

  return conversation
    .map((message) => `${message.role === "assistant" ? "Assistant" : "User"}: ${message.text}`)
    .join("\n");
}

function formatCoachContext(context) {
  const label = context?.kind === "draft_editing"
    ? "Draft editing"
    : context?.kind === "active_workout"
      ? "Active workout"
      : "Planning";

  if (context?.kind !== "active_workout" || !context?.activeWorkout) {
    return label;
  }

  const lines = [
    label,
    `Routine: ${context.activeWorkout.routineName || "Current workout"}`,
    `Exercises: ${(context.activeWorkout.exercises || []).join(", ") || "None listed"}`
  ];

  if (context.activeWorkout.routineID) {
    lines.push(`Routine id: ${context.activeWorkout.routineID}`);
  }

  if (context.activeWorkout.nextExercise) {
    lines.push(`Next exercise: ${context.activeWorkout.nextExercise}`);
  }

  if (context.activeWorkout.checkInNote) {
    lines.push(`Post-workout check-in that needs a real conversation (address it directly in your first reply): ${context.activeWorkout.checkInNote}`);
  }

  return lines.join("\n");
}

function sanitizeReply(reply) {
  const cleaned = typeof reply === "string" ? reply.trim() : "";
  return cleaned || "I kept the draft aligned with what you asked for.";
}

function sanitizeCoachAction(action) {
  const cleaned = typeof action === "string" ? action.trim().toLowerCase() : "";

  if (cleaned === "reply_only" || cleaned === "suggestion" || cleaned === "created_draft" || cleaned === "updated_draft") {
    return cleaned;
  }

  return "reply_only";
}

function sanitizeChangeSummary(changeSummary, action) {
  const sanitizedAction = sanitizeCoachAction(action);
  if (sanitizedAction !== "created_draft" && sanitizedAction !== "updated_draft") {
    return null;
  }

  const cleaned = typeof changeSummary === "string" ? changeSummary.trim() : "";
  return cleaned || "I updated the draft to match your latest request.";
}

function sanitizeOptionalRoutine(routine, action) {
  const sanitizedAction = sanitizeCoachAction(action);
  if (sanitizedAction !== "created_draft" && sanitizedAction !== "updated_draft") {
    return null;
  }

  return sanitizeRoutine(routine);
}

function sanitizeOptionalPhotoWorkoutExtraction(extraction, action) {
  if (sanitizeCoachAction(action) !== "updated_draft") {
    return null;
  }

  return sanitizePhotoWorkoutExtraction(extraction);
}

function sanitizeExerciseSwapSuggestions(suggestions, candidates) {
  const validNames = new Set(
    (Array.isArray(candidates) ? candidates : [])
      .map((candidate) => String(candidate?.name ?? "").trim().toLowerCase())
      .filter(Boolean)
  );

  const cleaned = (Array.isArray(suggestions) ? suggestions : [])
    .map((suggestion) => ({
      exerciseName: String(suggestion?.exerciseName ?? "").trim(),
      reason: String(suggestion?.reason ?? "").trim(),
      preserves: Array.isArray(suggestion?.preserves)
        ? suggestion.preserves.map((value) => String(value).trim()).filter(Boolean).slice(0, 4)
        : [],
      caution: typeof suggestion?.caution === "string" ? suggestion.caution.trim() : null
    }))
    .filter((suggestion) =>
      suggestion.exerciseName &&
      suggestion.reason &&
      validNames.has(suggestion.exerciseName.toLowerCase())
    );

  if (cleaned.length === 0) {
    throw new Error("The suggested exercise swaps were incomplete.");
  }

  return cleaned.slice(0, 4);
}

function sanitizeExerciseCoachSuggestions(suggestions, candidates) {
  const validNames = new Set(
    (Array.isArray(candidates) ? candidates : [])
      .map((candidate) => String(candidate?.name ?? "").trim().toLowerCase())
      .filter(Boolean)
  );

  return (Array.isArray(suggestions) ? suggestions : [])
    .map((suggestion) => ({
      exerciseName: String(suggestion?.exerciseName ?? "").trim(),
      reason: String(suggestion?.reason ?? "").trim()
    }))
    .filter((suggestion) =>
      suggestion.exerciseName &&
      suggestion.reason &&
      validNames.has(suggestion.exerciseName.toLowerCase())
    )
    .slice(0, 3);
}

function sanitizeCoachAnswer(answer) {
  const cleaned = typeof answer === "string" ? answer.trim() : "";

  if (!cleaned) {
    throw new Error("The exercise coach answer was incomplete.");
  }

  return cleaned;
}

function sanitizeRoutine(routine) {
  const title = typeof routine?.title === "string" ? routine.title.trim() : "";
  const summary = typeof routine?.summary === "string" ? routine.summary.trim() : "";
  const rationale = typeof routine?.rationale === "string" ? routine.rationale.trim() : "";
  const routineNotes = Array.isArray(routine?.routineNotes)
    ? routine.routineNotes
        .map((note) => String(note).trim())
        .filter(Boolean)
    : [];

  const exercises = Array.isArray(routine?.exercises)
    ? routine.exercises
        .map((exercise) => {
          const name = String(exercise?.name ?? "").trim();

          // The model's own catalogMatch claim is only an incentive to copy
          // names verbatim; the server holds the full catalog, so membership
          // is recomputed here and the recomputed value wins.
          const catalogMatch = catalogNameSet.size > 0
            ? catalogNameSet.has(name.toLowerCase())
            : (typeof exercise?.catalogMatch === "boolean" ? exercise.catalogMatch : undefined);

          return {
            name,
            sets: clampNumber(Number(exercise?.sets ?? 3), 1, 10),
            reps: String(exercise?.reps ?? "").trim(),
            notes: String(exercise?.notes ?? "").trim(),
            reasoning: String(exercise?.reasoning ?? "").trim(),
            tip: String(exercise?.tip ?? "").trim(),
            catalogMatch
          };
        })
        .filter((exercise) => exercise.name && exercise.reps)
    : [];

  if (!title || exercises.length === 0) {
    throw new Error("The generated routine was incomplete.");
  }

  return {
    title,
    summary,
    rationale,
    routineNotes,
    exercises
  };
}

// The nudge contract the app can trust: the response mirrors the REQUEST's
// exercise list byte for byte — same names, same order — carrying only
// target deltas. A model that invents an exercise name fails the request;
// an exercise it skipped comes back all-null (no change).
function sanitizeWorkoutNudge(nudge, routine) {
  const textOrNull = (input, maxLength) =>
    typeof input === "string" && input.trim() ? input.trim().slice(0, maxLength) : null;
  const clampWords = (text, maxWords) =>
    text.split(/\s+/).filter(Boolean).slice(0, maxWords).join(" ");

  const requestNames = new Set(routine.exercises.map((exercise) => exercise.name.toLowerCase()));
  const byName = new Map();

  for (const item of (Array.isArray(nudge?.exercises) ? nudge.exercises : [])) {
    const itemName = String(item?.name ?? "").trim();
    if (!requestNames.has(itemName.toLowerCase())) {
      throw new Error("The nudge referenced an exercise that is not in the routine.");
    }
    if (!byName.has(itemName.toLowerCase())) {
      byName.set(itemName.toLowerCase(), item);
    }
  }

  const exercises = routine.exercises.map((exercise) => {
    const item = byName.get(exercise.name.toLowerCase()) ?? null;
    const setCount = Number.isInteger(item?.setCount) ? clampNumber(item.setCount, 1, 10) : null;
    const suggestedWeightText = textOrNull(item?.suggestedWeightText, 24);
    const repText = textOrNull(item?.repText, 24);
    const rawWhyNote = textOrNull(item?.whyNote, 120);
    const hasChange = setCount !== null || suggestedWeightText !== null || repText !== null;

    return {
      // Echo the request's own name, byte for byte.
      name: exercise.name,
      suggestedWeightText,
      repText,
      setCount,
      whyNote: hasChange && rawWhyNote ? clampWords(rawWhyNote, 12) : null
    };
  });

  return {
    overallNote: textOrNull(nudge?.overallNote, 160),
    exercises
  };
}

function sanitizePhotoWorkoutExtraction(extraction) {
  const days = Array.isArray(extraction?.days)
    ? extraction.days
        .map((day, index) => sanitizePhotoWorkoutDay(day, index))
        .filter((day) => day.exercises.length > 0 || day.notes.length > 0 || day.name)
    : [];

  const rawText = typeof extraction?.rawText === "string" ? extraction.rawText.trim() : "";

  return {
    rawText: rawText || derivePhotoWorkoutRawText(days),
    days
  };
}

function sanitizePhotoWorkoutDay(day, index) {
  const name = typeof day?.name === "string" ? day.name.trim() : "";
  const sourceHeading = typeof day?.sourceHeading === "string" ? day.sourceHeading.trim() : "";
  const notes = Array.isArray(day?.notes)
    ? day.notes
        .map((note) => String(note).trim())
        .filter(Boolean)
    : [];

  const exercises = Array.isArray(day?.exercises)
    ? day.exercises
        .map((exercise) => sanitizePhotoWorkoutExercise(exercise))
        .filter((exercise) => exercise.exerciseText || exercise.sourceText)
    : [];

  return {
    name: name || (index === 0 ? "Imported Workout" : `Imported Day ${index + 1}`),
    sourceHeading: sourceHeading || null,
    notes,
    exercises
  };
}

function sanitizePhotoWorkoutExercise(exercise) {
  const sourceText = String(exercise?.sourceText ?? "").trim();
  const exerciseText = String(exercise?.exerciseText ?? "").trim();
  const notes = Array.isArray(exercise?.notes)
    ? exercise.notes
        .map((note) => String(note).trim())
        .filter(Boolean)
    : [];
  const intensityNotes = Array.isArray(exercise?.intensityNotes)
    ? exercise.intensityNotes
        .map((note) => String(note).trim())
        .filter(Boolean)
    : [];

  return {
    sourceText: sourceText || exerciseText,
    exerciseText: exerciseText || sourceText,
    setCount: Number.isFinite(exercise?.setCount) ? clampNumber(exercise.setCount, 1, 20) : null,
    repText: typeof exercise?.repText === "string" && exercise.repText.trim() ? exercise.repText.trim() : null,
    notes,
    restSeconds: Number.isFinite(exercise?.restSeconds) ? clampNumber(exercise.restSeconds, 0, 1800) : null,
    intensityNotes
  };
}

function derivePhotoWorkoutRawText(days) {
  return days
    .flatMap((day) => [
      day.sourceHeading,
      ...day.notes,
      ...day.exercises.map((exercise) => exercise.sourceText)
    ])
    .filter(Boolean)
    .join("\n")
    .trim();
}

function clampNumber(value, minimum, maximum) {
  if (!Number.isFinite(value)) {
    return minimum;
  }

  return Math.min(Math.max(Math.round(value), minimum), maximum);
}

function readJsonBody(request, response) {
  return new Promise((resolve, reject) => {
    let rawBody = "";
    let receivedBytes = 0;
    let rejectedForSize = false;

    const rejectTooLarge = () => {
      rejectedForSize = true;
      // Stop the upload once the 413 has flushed; until then, oversized
      // chunks are discarded (rejectedForSize guard), so memory stays flat.
      response.on("finish", () => request.destroy());
      sendJson(response, 413, {
        error: `Request body too large. Limit is ${maxBodyBytes} bytes.`
      });
      reject(new Error("Request body too large."));
    };

    const declaredLength = Number(request.headers["content-length"]);
    if (Number.isFinite(declaredLength) && declaredLength > maxBodyBytes) {
      rejectTooLarge();
      return;
    }

    request.on("data", (chunk) => {
      if (rejectedForSize) return;

      receivedBytes += chunk.length;
      if (receivedBytes > maxBodyBytes) {
        rejectTooLarge();
        return;
      }

      rawBody += chunk;
    });

    request.on("end", () => {
      if (rejectedForSize) return;

      if (!rawBody) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(rawBody));
      } catch {
        reject(new Error("Request body must be valid JSON."));
      }
    });

    request.on("error", (error) => {
      if (rejectedForSize) return;
      reject(error);
    });
  });
}

function sendJson(response, statusCode, payload) {
  if (response.writableEnded) return;

  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8"
  });
  response.end(JSON.stringify(payload));
}
