import http from "node:http";

const port = Number(process.env.PORT ?? 8787);
const workoutGeneratorModel = process.env.OPENAI_MODEL ?? "gpt-4.1";
const photoImportModel = process.env.OPENAI_PHOTO_IMPORT_MODEL ?? "gpt-4.1-mini";
const transcriptionModel = process.env.OPENAI_TRANSCRIBE_MODEL ?? "gpt-4o-mini-transcribe";
const apiKey = process.env.OPENAI_API_KEY ?? "";

const workoutSchema = {
  type: "object",
  additionalProperties: false,
  required: ["title", "summary", "rationale", "routineNotes", "exercises"],
  properties: {
    title: { type: "string" },
    summary: { type: "string" },
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
        required: ["name", "sets", "reps", "notes"],
        properties: {
          name: { type: "string" },
          sets: { type: "integer", minimum: 1, maximum: 10 },
          reps: { type: "string" },
          notes: { type: "string" }
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

const coachChatSchema = {
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

const workoutGeneratorInstructions = [
  "You write practical gym routines for a workout tracking app.",
  "Match the user's requested split, equipment, time cap, and goal as closely as possible.",
  "Prefer clear, standard exercise names that make sense inside a routine builder.",
  "The name field must contain only the exercise name, never sets, reps, numbering, or prescription text.",
  "Keep the plan efficient and realistic for the requested duration.",
  "Include a short rationale that explains why this workout structure fits the user's request.",
  "The rationale should read like a concise coach note, not hidden reasoning or a step-by-step chain of thought.",
  "The summary should read like a practical overview of the session, not generic app copy.",
  "Routine notes should feel like useful coaching reminders, not filler.",
  coachVoiceGuidelines,
  preferenceInstructions,
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
  "The name field must contain only the exercise name, never sets, reps, numbering, or prescription text.",
  "Use the summary to explain what the add-on is for in plain English.",
  "Use the rationale like a concise coach note about why this small block fits.",
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
  "The name field must contain only the exercise name, never sets, reps, numbering, or prescription text.",
  "Update the rationale so it briefly explains why the revised version fits the user's request.",
  "The rationale should stay concise and user-facing, not hidden reasoning or chain-of-thought.",
  "Write reply as a short coach-style response that explains what changed and why.",
  "When action is updated_draft, fill changeSummary with one short plain-English sentence describing the change.",
  "When action is reply_only or suggestion, set routine to null and changeSummary to null.",
  coachVoiceGuidelines,
  preferenceInstructions,
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
  "Choose action reply_only when the user mainly wants an answer, reassurance, or explanation.",
  "Choose action suggestion when you want to recommend a change but should not edit the draft yet.",
  "Choose action created_draft when the user clearly wants a new structured workout and there is no current routine yet.",
  "Choose action updated_draft when there is a current routine and the user clearly wants it changed right now.",
  "If the user is in active workout context, prefer practical coaching help unless they clearly ask for the rest of the workout to be rebuilt.",
  "When action is created_draft or updated_draft, return a complete routine in the schema and write a short changeSummary.",
  "When action is reply_only or suggestion, set routine to null and changeSummary to null.",
  "If a routine is returned, keep the name field to exercise names only, never sets, reps, numbering, or prescription text.",
  coachVoiceGuidelines,
  preferenceInstructions,
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

  if (request.method === "POST" && request.url === "/api/ai/workout-generator") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request);
      const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
      const preferences = normalizePreferences(body?.preferences);

      if (prompt.length < 8) {
        sendJson(response, 400, {
          error: "Prompt must be at least 8 characters long."
        });
        return;
      }

      const routineResult = await generateWorkoutRoutine(prompt, preferences);

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

      const body = await readJsonBody(request);
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

      const body = await readJsonBody(request);
      const editPrompt = typeof body?.editPrompt === "string" ? body.editPrompt.trim() : "";
      const currentRoutine = body?.currentRoutine ?? null;
      const conversation = normalizeConversation(body?.conversation);
      const preferences = normalizePreferences(body?.preferences);

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

      const routineResult = await reviseWorkoutRoutine({ editPrompt, currentRoutine, conversation, preferences });

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

  if (request.method === "POST" && request.url === "/api/ai/photo-to-workout/extract") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request);
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

      const body = await readJsonBody(request);
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

      const body = await readJsonBody(request);
      const message = typeof body?.message === "string" ? body.message.trim() : "";
      const conversation = normalizeConversation(body?.conversation);
      const currentRoutine = body?.currentRoutine ?? null;
      const context = normalizeCoachContext(body?.context);
      const preferences = normalizePreferences(body?.preferences);

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
        preferences
      });

      sendJson(response, 200, {
        reply: coachResult.reply,
        action: coachResult.action,
        changeSummary: coachResult.changeSummary,
        routine: coachResult.routine,
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

      const body = await readJsonBody(request);
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

      const body = await readJsonBody(request);
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

  if (request.method === "POST" && request.url === "/api/ai/voice-to-workout/transcribe") {
    try {
      if (!apiKey) {
        sendJson(response, 500, {
          error: "OPENAI_API_KEY is missing on the backend."
        });
        return;
      }

      const body = await readJsonBody(request);
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

  sendJson(response, 404, {
    error: "Route not found."
  });
});

server.listen(port, () => {
  console.log(`Lokt AI backend listening on http://127.0.0.1:${port}`);
});

async function generateWorkoutRoutine(prompt, preferences) {
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
      input: formatPromptWithPreferences(prompt, preferences),
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
      input: formatPromptWithPreferences(prompt, preferences),
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

async function reviseWorkoutRoutine({ editPrompt, currentRoutine, conversation, preferences }) {
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

async function chatWithCoach({ message, conversation, currentRoutine, context, preferences }) {
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
                "Saved user preferences:",
                formatPreferences(preferences),
                "",
                "Earlier conversation:",
                formatConversation(conversation),
                "",
                "Latest user message:",
                message
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

  return {
    requestId: payload.id ?? null,
    action: sanitizeCoachAction(coachResponse?.action),
    reply: sanitizeReply(coachResponse?.reply),
    changeSummary: sanitizeChangeSummary(coachResponse?.changeSummary, coachResponse?.action),
    routine: sanitizeOptionalRoutine(coachResponse?.routine, coachResponse?.action)
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
          routineName: typeof activeWorkout.routineName === "string" ? activeWorkout.routineName.trim() : "",
          exercises: Array.isArray(activeWorkout.exercises)
            ? activeWorkout.exercises.map((item) => String(item).trim()).filter(Boolean).slice(0, 20)
            : [],
          nextExercise: typeof activeWorkout.nextExercise === "string" ? activeWorkout.nextExercise.trim() : ""
        }
      : null
  };
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

function formatPromptWithPreferences(prompt, preferences) {
  return [
    "User request:",
    prompt,
    "",
    "Saved user preferences:",
    formatPreferences(preferences)
  ].join("\n");
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

  if (context.activeWorkout.nextExercise) {
    lines.push(`Next exercise: ${context.activeWorkout.nextExercise}`);
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
        .map((exercise) => ({
          name: String(exercise?.name ?? "").trim(),
          sets: clampNumber(Number(exercise?.sets ?? 3), 1, 10),
          reps: String(exercise?.reps ?? "").trim(),
          notes: String(exercise?.notes ?? "").trim()
        }))
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

function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    let rawBody = "";

    request.on("data", (chunk) => {
      rawBody += chunk;
    });

    request.on("end", () => {
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

    request.on("error", reject);
  });
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8"
  });
  response.end(JSON.stringify(payload));
}
