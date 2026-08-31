#!/usr/bin/env node
// run-personas.mjs — Lokt synthetic-user focus group.
//
// Simulates the APP's request construction for each persona in this directory
// against the real backend (:8787), then has each persona review its own
// journey log and file complaints (direct OpenAI Responses call, gpt-4.1-mini),
// then triages all complaints into one ranked list.
//
// Run (from the repo root — the key stays in process env, never in a file we read):
//   node --env-file=backend/.env harness/personas/run-personas.mjs
//
// Flags:
//   --dry-run          build every payload (incl. memory digests), no network
//   --personas a,b     run a subset by persona id
//   --skip-complaints  journeys only, no OpenAI-direct complaint/triage calls
//   --base URL         backend base (default http://127.0.0.1:8787)
//
// SECRETS: this script NEVER prints or persists env values. Journey logs record
// request bodies + response bodies only (no headers). A final scan aborts if
// any written file contains key material.

import { readFileSync, readdirSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const opt = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};

const DRY_RUN = flag("--dry-run");
const SKIP_COMPLAINTS = flag("--skip-complaints");
const BASE = opt("--base", "http://127.0.0.1:8787");
const ONLY = opt("--personas", "").split(",").map((s) => s.trim()).filter(Boolean);

const APP_TOKEN = process.env.APP_TOKEN ?? "";
const OPENAI_KEY = process.env.OPENAI_API_KEY ?? "";
const BACKEND_LOG = "/tmp/lokt-backend.log";

const MIN_CALL_SPACING_MS = 2100;   // backend rate limit is 40/600s — never trip it
const MAX_BACKEND_CALLS = 45;       // hard safety guard for a full sweep
const CALL_TIMEOUT_MS = 150000;

// $/1M tokens. Backend labels → model. Update if backend models change.
const PRICING = {
  "gpt-4.1": { input: 2.0, output: 8.0 },
  "gpt-4.1-mini": { input: 0.4, output: 1.6 }
};
const LABEL_MODEL = (label) =>
  label === "voice-to-workout/parse" || label === "photo-to-workout/extract" ? "gpt-4.1-mini" : "gpt-4.1";

// ---------------------------------------------------------------- utilities

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function fnv1a(text, seed = 0x811c9dc5) {
  let hash = seed >>> 0;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

// Deterministic PRNG per persona → reproducible temperament sampling.
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function deterministicUUID(text) {
  const hex = [0, 1, 2, 3].map((n) => fnv1a(`${text}#${n}`).toString(16).padStart(8, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`.toUpperCase();
}

const fmtDate = (date) => {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
};
const daysAgo = (n) => {
  const d = new Date();
  d.setHours(12, 0, 0, 0);
  d.setDate(d.getDate() - n);
  return d;
};
const formattedWeight = (w) => (w === Math.round(w) ? String(Math.round(w)) : w.toFixed(1));
const epley = (weight, reps) => weight * (1 + reps / 30);

function pickWeighted(rng, weights) {
  const entries = Object.entries(weights).filter(([, w]) => w > 0);
  const total = entries.reduce((sum, [, w]) => sum + w, 0);
  let roll = rng() * total;
  for (const [value, w] of entries) {
    roll -= w;
    if (roll <= 0) return value;
  }
  return entries[entries.length - 1]?.[0] ?? "about right";
}

// ------------------------------------------------- simulated user memory
//
// Mirrors the serialized shape of UserMemoryStore.swift's tiered digest
// (recent ≤14d per-session / 15–90d weekly / lifetime facts) and stays inside
// the backend's normalizeUserMemory clamps. Synthetic data only.

function simulateHistory(persona, routineName) {
  const history = persona.history;
  const temperament = persona.checkInTemperament;
  const rng = mulberry32(fnv1a(persona.id));
  const sessions = [];
  const dayOffsets = [0, 2, 4, 5, 1, 3, 6];
  const missedPerWeek = temperament.missedSessionsPerWeek ?? 0;

  const bestByExercise = new Map(); // name → {value, date}
  const firstSeen = new Map();

  for (let week = history.startWeeksAgo; week >= 1; week -= 1) {
    const weekIndex = history.startWeeksAgo - week; // 0 = first week of usage
    let planned = history.sessionsPerWeek;
    if (missedPerWeek > 0 && rng() < 0.8) planned = Math.max(1, planned - missedPerWeek);

    for (let i = 0; i < planned; i += 1) {
      const date = daysAgo(week * 7 - dayOffsets[i % dayOffsets.length]);
      if (date > new Date()) continue;

      const lifts = history.liftPool.map((lift) => ({
        ...lift,
        weight: lift.weight > 0 ? lift.weight + (lift.weeklyBump ?? 0) * weekIndex : 0
      }));

      const setsPerLift = 3;
      const volume = Math.round(lifts.reduce((sum, l) => sum + (l.weight > 0 ? l.weight * l.reps * setsPerLift : 0), 0));
      const checkIn = pickWeighted(rng, temperament.weights);
      const hadPain = rng() < (temperament.painRate ?? 0);
      const painNote = hadPain
        ? temperament.painNotes[sessions.length % temperament.painNotes.length]
        : null;

      const prs = [];
      for (const lift of lifts) {
        if (!firstSeen.has(lift.name)) firstSeen.set(lift.name, date);
        if (lift.weight <= 0) continue;
        const e1rm = epley(lift.weight, lift.reps);
        const prior = bestByExercise.get(lift.name);
        if (!prior) {
          bestByExercise.set(lift.name, { value: e1rm, date });
        } else if (e1rm > prior.value) {
          prs.push(`PR: ${lift.name} e1RM ${formattedWeight(Math.round(e1rm))}`);
          bestByExercise.set(lift.name, { value: e1rm, date });
        }
      }

      const bestSets = lifts
        .map((l) => ({
          line: l.weight > 0
            ? `${l.name} ${formattedWeight(l.weight)}x${l.reps} (e1RM ${formattedWeight(Math.round(epley(l.weight, l.reps)))})`
            : `${l.name} x${l.reps}`,
          sort: l.weight > 0 ? epley(l.weight, l.reps) : l.reps / 1000
        }))
        .sort((a, b) => b.sort - a.sort)
        .slice(0, 6)
        .map((entry) => entry.line);

      sessions.push({
        date, routine: routineName,
        sets: lifts.length * setsPerLift, volume,
        durationMinutes: history.sessionDurationMinutes + Math.floor(rng() * 7) - 3,
        checkIn, painNote, bestSets, prs,
        groups: lifts.map((l) => l.group)
      });
    }
  }

  sessions.sort((a, b) => a.date - b.date);
  return { sessions, bestByExercise, firstSeen };
}

function buildMemoryDigest(persona, routineName) {
  const { sessions, bestByExercise, firstSeen } = simulateHistory(persona, routineName);
  if (sessions.length === 0) return null;

  const recentCutoff = daysAgo(14);
  recentCutoff.setHours(0, 0, 0, 0);

  const recent = sessions.filter((s) => s.date >= recentCutoff);
  const mid = sessions.filter((s) => s.date < recentCutoff);

  const recentSessions = recent
    .slice()
    .reverse()
    .map((s) => {
      const entry = { date: fmtDate(s.date), routine: s.routine, sets: s.sets };
      if (s.volume > 0) entry.volume = s.volume;
      entry.durationMinutes = s.durationMinutes;
      entry.checkIn = s.checkIn;
      if (s.painNote) entry.painNote = s.painNote;
      if (s.bestSets.length > 0) entry.bestSets = s.bestSets;
      if (s.prs.length > 0) entry.prs = s.prs;
      return entry;
    });

  // Weekly summaries for the 15–90 day tier (week anchored to Sunday).
  const weeks = new Map();
  for (const s of mid) {
    const weekStart = new Date(s.date);
    weekStart.setDate(weekStart.getDate() - weekStart.getDay());
    const key = fmtDate(weekStart);
    if (!weeks.has(key)) weeks.set(key, []);
    weeks.get(key).push(s);
  }
  const weeklySummaries = [...weeks.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1))
    .map(([weekOf, entries]) => {
      const summary = { weekOf, sessions: entries.length };
      summary.sets = entries.reduce((sum, s) => sum + s.sets, 0);
      const volume = entries.reduce((sum, s) => sum + s.volume, 0);
      if (volume > 0) summary.volume = volume;
      const groupCounts = new Map();
      for (const s of entries) for (const g of s.groups) groupCounts.set(g, (groupCounts.get(g) ?? 0) + 3);
      const focus = [...groupCounts.entries()]
        .filter(([g]) => ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core"].includes(g))
        .sort((a, b) => (b[1] !== a[1] ? b[1] - a[1] : a[0] < b[0] ? -1 : 1))
        .slice(0, 2)
        .map(([g]) => g);
      if (focus.length > 0) summary.focus = focus;
      const prs = entries.flatMap((s) => s.prs);
      if (prs.length > 0) summary.prs = prs;
      const introduced = [...firstSeen.entries()]
        .filter(([, date]) => {
          const start = new Date(weekOf); start.setHours(0, 0, 0, 0);
          const end = new Date(start); end.setDate(end.getDate() + 7);
          return date >= start && date < end;
        })
        .map(([name]) => name)
        .sort()
        .slice(0, 5);
      if (introduced.length > 0) summary.introduced = introduced;
      return summary;
    });

  const first = sessions[0];
  const totalVolume = sessions.reduce((sum, s) => sum + s.volume, 0);
  const weeksSpan = Math.max(1, Math.round((Date.now() - first.date.getTime()) / (7 * 86400000)) + 1);
  const weekStartsSet = new Set(sessions.map((s) => {
    const d = new Date(s.date); d.setDate(d.getDate() - d.getDay()); return fmtDate(d);
  }));

  const allTimePRs = [...bestByExercise.entries()]
    .sort((a, b) => b[1].value - a[1].value)
    .slice(0, 10)
    .map(([name, best]) => `${name} e1RM ${formattedWeight(Math.round(best.value))} (${fmtDate(best.date)})`);

  const painHistory = sessions
    .filter((s) => s.painNote)
    .slice(-8)
    .reverse()
    .map((s) => `${fmtDate(s.date)}: ${s.painNote}`);

  const lifetime = {
    since: fmtDate(first.date),
    totalSessions: sessions.length,
    sessionsPerWeek: Math.round((sessions.length / weeksSpan) * 10) / 10,
    longestStreakWeeks: weekStartsSet.size
  };
  if (totalVolume > 0) lifetime.totalVolume = totalVolume;
  if (allTimePRs.length > 0) lifetime.allTimePRs = allTimePRs;
  if (painHistory.length > 0) lifetime.painHistory = painHistory;
  const limitations = (persona.preferences.limitations ?? "").trim();
  if (limitations) lifetime.limitations = limitations;

  const digest = {
    schemaVersion: 1,
    // Swift's JSONEncoder default: seconds since 2001-01-01 reference date.
    generatedAt: Date.now() / 1000 - 978307200,
    sourceSessionCount: sessions.length
  };
  if (recentSessions.length > 0) digest.recentSessions = recentSessions;
  if (weeklySummaries.length > 0) digest.weeklySummaries = weeklySummaries;
  digest.lifetime = lifetime;
  return digest;
}

// ------------------------------------------------------------ backend client

let backendCallCount = 0;
let lastCallAt = 0;

async function backendPost(path, body) {
  backendCallCount += 1;
  if (backendCallCount > MAX_BACKEND_CALLS) {
    throw new Error(`Backend call budget exceeded (${MAX_BACKEND_CALLS}). Aborting.`);
  }

  const headers = { "content-type": "application/json" };
  if (APP_TOKEN) headers["x-app-token"] = APP_TOKEN;

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const sinceLast = Date.now() - lastCallAt;
    if (sinceLast < MIN_CALL_SPACING_MS) await sleep(MIN_CALL_SPACING_MS - sinceLast);
    lastCallAt = Date.now();

    const started = Date.now();
    const response = await fetch(`${BASE}${path}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(CALL_TIMEOUT_MS)
    });
    const ms = Date.now() - started;
    const payload = await response.json().catch(() => ({ error: "unparseable response body" }));

    if (response.status === 429 && attempt < 3) {
      const retryAfter = Number(payload?.retryAfter ?? response.headers.get("retry-after") ?? 15);
      console.log(`    429 on ${path} — waiting ${retryAfter + 1}s (attempt ${attempt})`);
      await sleep((retryAfter + 1) * 1000);
      continue;
    }

    return { status: response.status, ms, body: payload };
  }
  return { status: 429, ms: 0, body: { error: "rate-limited after retries" } };
}

// ------------------------------------------------------------- journey steps

function routineToPayload(routine) {
  // Round-trip the backend routine into the same shape the app resubmits.
  return {
    title: routine?.title ?? "Untitled",
    summary: routine?.summary ?? "",
    rationale: routine?.rationale ?? "",
    routineNotes: Array.isArray(routine?.routineNotes) ? routine.routineNotes : [],
    exercises: (Array.isArray(routine?.exercises) ? routine.exercises : []).map((e) => ({
      name: e?.name ?? "",
      sets: Number.isInteger(e?.sets) ? e.sets : 3,
      reps: e?.reps ?? "8-12",
      notes: e?.notes ?? "",
      reasoning: e?.reasoning,
      tip: e?.tip,
      catalogMatch: e?.catalogMatch
    }))
  };
}

function savedRoutinePayload(persona, routine) {
  return {
    id: deterministicUUID(persona.id),
    name: routine?.title ?? "My routine",
    exercises: (routine?.exercises ?? []).slice(0, 20).map((e) => ({
      name: e.name, sets: e.sets, reps: e.reps
    }))
  };
}

async function runJourney(persona) {
  const log = { persona: persona.id, name: persona.name, startedAt: new Date().toISOString(), steps: [] };
  const record = (step, endpoint, request, result) => {
    log.steps.push({ step, endpoint, request, status: result?.status ?? null, ms: result?.ms ?? null, response: result?.body ?? null });
  };
  const preferences = persona.preferences;

  console.log(`\n== ${persona.name} (${persona.id}) ==`);

  // 1. Initial generation — mirrors AIWorkoutGeneratorRequest (fresh install: no memory).
  console.log("  step 1/5 generate");
  const generateBody = { prompt: persona.journey.initialPrompt, preferences };
  const generated = DRY_RUN ? null : await backendPost("/api/ai/workout-generator", generateBody);
  record("generate", "/api/ai/workout-generator", generateBody, generated);
  const initialRoutine = generated?.body?.routine ?? null;
  if (!DRY_RUN && !initialRoutine) {
    console.log(`    generation failed (${generated?.status}) — aborting journey`);
    return log;
  }

  // 2. In-character edit — mirrors AIWorkoutGeneratorRevisionRequest.
  console.log("  step 2/5 revise");
  const reviseBody = {
    editPrompt: persona.journey.editPrompt,
    currentRoutine: routineToPayload(initialRoutine ?? { title: "(dry-run placeholder)" }),
    conversation: [],
    preferences
  };
  const revised = DRY_RUN ? null : await backendPost("/api/ai/workout-generator/revise", reviseBody);
  record("revise", "/api/ai/workout-generator/revise", reviseBody, revised);
  const workingRoutine = revised?.body?.routine ?? initialRoutine;

  // The persona "saves" the revised routine — its id anchors coach edits.
  const saved = savedRoutinePayload(persona, workingRoutine ?? { title: "My routine", exercises: [] });

  // 3. Coach chat (planning) — question or second edit, mirrors CoachChatRequest.
  console.log("  step 3/5 coach chat");
  const coachBody = {
    message: persona.journey.coachMessage,
    conversation: [],
    context: { kind: "planning", activeWorkout: null },
    savedRoutines: [saved],
    preferences
  };
  const coach = DRY_RUN ? null : await backendPost("/api/ai/coach/chat", coachBody);
  record("coach", "/api/ai/coach/chat", coachBody, coach);

  // 4. Voice import — persona-phrased rambling transcript.
  console.log("  step 4/5 voice parse");
  const voiceBody = { transcript: persona.journey.voiceTranscript };
  const voice = DRY_RUN ? null : await backendPost("/api/ai/voice-to-workout/parse", voiceBody);
  record("voice", "/api/ai/voice-to-workout/parse", voiceBody, voice);

  // 5. Weeks later — evolving memory digest (per temperament) rides along and
  //    the coach is asked a question that should reflect that history.
  console.log("  step 5/5 follow-up with 3-week memory");
  const memory = buildMemoryDigest(persona, saved.name);
  log.memoryDigestBytes = memory ? JSON.stringify(memory).length : 0;
  const followUpBody = {
    message: persona.journey.followUpMessage,
    conversation: [],
    context: { kind: "planning", activeWorkout: null },
    savedRoutines: [saved],
    preferences,
    memory
  };
  const followUp = DRY_RUN ? null : await backendPost("/api/ai/coach/chat", followUpBody);
  record("followup", "/api/ai/coach/chat", followUpBody, followUp);

  log.finishedAt = new Date().toISOString();
  return log;
}

// -------------------------------------------------- complaint + triage calls
// These go DIRECTLY to OpenAI (gpt-4.1-mini) — personas are research tooling,
// not an app surface, so they must not pollute the system under test.

let directUsage = { input: 0, output: 0, calls: 0 };

async function openaiJson({ instructions, inputText, schemaName, schema }) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "gpt-4.1-mini",
      store: false,
      instructions,
      input: [{ role: "user", content: [{ type: "input_text", text: inputText }] }],
      text: { format: { type: "json_schema", name: schemaName, strict: true, schema } }
    }),
    signal: AbortSignal.timeout(CALL_TIMEOUT_MS)
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload?.error?.message ?? `OpenAI call failed (${response.status})`);
  directUsage.calls += 1;
  directUsage.input += payload?.usage?.input_tokens ?? 0;
  directUsage.output += payload?.usage?.output_tokens ?? 0;
  const text = (payload?.output ?? [])
    .flatMap((item) => item?.content ?? [])
    .filter((c) => c?.type === "output_text")
    .map((c) => c.text)
    .join("");
  return JSON.parse(text);
}

const STEP_ENUM = ["generate", "revise", "coach", "voice", "followup"];

const complaintSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    complaints: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          title: { type: "string", description: "Short issue name, 3-8 words" },
          complaint: { type: "string", description: "First-person, in-character complaint, 1-3 sentences" },
          evidenceStep: { type: "string", enum: STEP_ENUM },
          evidenceQuote: { type: "string", description: "Verbatim excerpt (<=200 chars) from the APP'S response that caused this" },
          severity: { type: "string", enum: ["blocker", "annoying", "nitpick"] },
          category: {
            type: "string",
            enum: ["constraint-violation", "safety", "math-consistency", "personalization", "clarity", "time", "exercise-selection", "tone", "other"]
          }
        },
        required: ["title", "complaint", "evidenceStep", "evidenceQuote", "severity", "category"]
      }
    },
    likes: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          what: { type: "string", description: "First-person, 1-2 sentences, something genuinely good" },
          evidenceStep: { type: "string", enum: STEP_ENUM }
        },
        required: ["what", "evidenceStep"]
      }
    }
  },
  required: ["complaints", "likes"]
};

function excerpt(value, max = 2600) {
  const text = typeof value === "string" ? value : JSON.stringify(value ?? null);
  return text.length > max ? `${text.slice(0, max)} …[truncated]` : text;
}

function routineDigest(routine) {
  if (!routine) return "(no routine returned)";
  const lines = [`Title: ${routine.title}`, `Summary: ${routine.summary}`];
  if (Array.isArray(routine.routineNotes) && routine.routineNotes.length > 0) {
    lines.push(`Routine notes: ${routine.routineNotes.join(" | ")}`);
  }
  for (const e of routine.exercises ?? []) {
    lines.push(`- ${e.name} — ${e.sets} sets x ${e.reps}${e.notes ? ` — notes: ${e.notes}` : ""}${e.reasoning ? ` — reasoning: ${e.reasoning}` : ""}${e.tip ? ` — tip: ${e.tip}` : ""}`);
  }
  return lines.join("\n");
}

function journeyDigest(persona, log) {
  const byStep = Object.fromEntries(log.steps.map((s) => [s.step, s]));
  const parts = [];

  const generated = byStep.generate;
  parts.push(`STEP "generate" — you asked: "${generated?.request?.prompt}"`,
    `The app answered (status ${generated?.status}):`,
    routineDigest(generated?.response?.routine), "");

  const revise = byStep.revise;
  parts.push(`STEP "revise" — you asked: "${revise?.request?.editPrompt}"`,
    `The app replied (status ${revise?.status}): "${excerpt(revise?.response?.reply ?? "", 600)}"`,
    `Change summary: ${revise?.response?.changeSummary ?? "(none)"}`,
    `Revised routine:`, routineDigest(revise?.response?.routine), "");

  const coach = byStep.coach;
  parts.push(`STEP "coach" — you asked: "${coach?.request?.message}"`,
    `Coach replied (status ${coach?.status}, action=${coach?.response?.action ?? "?"}${coach?.response?.editedRoutineID ? `, edited your saved routine` : ""}): "${excerpt(coach?.response?.reply ?? "", 1400)}"`,
    coach?.response?.routine ? `Coach's routine:\n${routineDigest(coach.response.routine)}` : "", "");

  const voice = byStep.voice;
  parts.push(`STEP "voice" — you rambled into the mic: "${voice?.request?.transcript}"`,
    `The app parsed it into (status ${voice?.status}): ${excerpt(voice?.response?.parse, 2200)}`, "");

  const follow = byStep.followup;
  const mem = follow?.request?.memory;
  const memSummary = mem
    ? `Your last 3 weeks of logs WERE attached to this request (check-ins: ${(mem.recentSessions ?? []).map((s) => s.checkIn + (s.painNote ? ` + pain: "${s.painNote}"` : "")).join("; ")}).`
    : "No history was attached.";
  parts.push(`STEP "followup" — three weeks later you asked: "${follow?.request?.message}"`,
    memSummary,
    `Coach replied (status ${follow?.status}, action=${follow?.response?.action ?? "?"}): "${excerpt(follow?.response?.reply ?? "", 1600)}"`,
    follow?.response?.routine ? `Coach's routine:\n${routineDigest(follow.response.routine)}` : "");

  return parts.filter(Boolean).join("\n");
}

async function complaintsFor(persona, log) {
  const instructions = [
    `You are roleplaying ${persona.name}: ${persona.oneLiner}`,
    `Profile: ${JSON.stringify(persona.profile)}`,
    `Your saved app preferences (the app KNOWS these): ${JSON.stringify(persona.preferences)}`,
    "",
    "You just reviewed your own journey log from a workout-coach app called Lokt.",
    "Write your TOP complaints (3-5) in first person, in character. Rules:",
    "- Every complaint must cite the step and a VERBATIM quote from the app's own output that caused it. Never invent quotes.",
    "- Complain only about what is actually visible in the log. If the app handled something well, do not manufacture a complaint about it.",
    "- severity: 'blocker' = it blocks your goal or violates your stated constraints/safety; 'annoying' = real friction; 'nitpick' = taste.",
    "- Also list 2-3 things you genuinely LIKED (signal, not flattery).",
    "- Stay true to your personality and tolerance. You are a real user, not a QA engineer: complain about how it made you feel and whether it fits your life."
  ].join("\n");
  return openaiJson({
    instructions,
    inputText: journeyDigest(persona, log),
    schemaName: "persona_feedback",
    schema: complaintSchema
  });
}

const triageSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    issues: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          title: { type: "string" },
          severity: { type: "string", enum: ["S1", "S2", "S3"] },
          kind: {
            type: "string",
            enum: ["constraint-violation", "safety", "math-consistency", "personalization", "clarity", "ux", "taste"]
          },
          personas: { type: "array", items: { type: "string" } },
          summary: { type: "string", description: "One neutral engineering-facing sentence" },
          representativeQuote: { type: "string", description: "The single strongest persona complaint quote" },
          refs: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              properties: { persona: { type: "string" }, complaintTitle: { type: "string" } },
              required: ["persona", "complaintTitle"]
            }
          }
        },
        required: ["title", "severity", "kind", "personas", "summary", "representativeQuote", "refs"]
      }
    }
  },
  required: ["issues"]
};

async function triage(allComplaints) {
  const instructions = [
    "You are triaging synthetic-user complaints about a workout-coach app for its developer.",
    "Merge duplicate/overlapping complaints across personas into single issues. Rank by severity:",
    "S1 = blocks a persona's goal, violates their stated constraints, or is a safety/math/consistency error.",
    "S2 = real friction that damages trust or usability.",
    "S3 = taste/preference.",
    "Keep persona attribution. Order issues most severe first. Do not invent issues not present in the input."
  ].join("\n");
  return openaiJson({
    instructions,
    inputText: JSON.stringify(allComplaints, null, 1),
    schemaName: "triage",
    schema: triageSchema
  });
}

// --------------------------------------------------------- cost accounting

// Offset in CHARACTERS (not statSync bytes): usageSince slices the decoded
// string, and multi-byte characters in the log would skew a byte offset —
// that once chopped the first [usage] line of a sweep out of the cost totals.
function backendLogSize() {
  try { return readFileSync(BACKEND_LOG, "utf8").length; } catch { return 0; }
}

function usageSince(offset) {
  let text = "";
  try {
    const whole = readFileSync(BACKEND_LOG, "utf8");
    text = whole.slice(Math.min(offset, whole.length));
  } catch { return { lines: [], cost: 0, byLabel: {} }; }

  const lines = [...text.matchAll(/\[usage\] (\S+) input=(\d+) output=(\d+)/g)]
    .map((m) => ({ label: m[1], input: Number(m[2]), output: Number(m[3]) }));
  const byLabel = {};
  let cost = 0;
  for (const line of lines) {
    const model = LABEL_MODEL(line.label);
    const price = PRICING[model];
    const lineCost = (line.input * price.input + line.output * price.output) / 1e6;
    cost += lineCost;
    const bucket = (byLabel[line.label] ??= { calls: 0, input: 0, output: 0, cost: 0 });
    bucket.calls += 1; bucket.input += line.input; bucket.output += line.output; bucket.cost += lineCost;
  }
  return { lines, cost, byLabel };
}

// ------------------------------------------------------------ secret hygiene

function assertNoSecrets(paths) {
  const needles = [APP_TOKEN, OPENAI_KEY].filter((v) => v && v.length >= 8);
  for (const path of paths) {
    const content = readFileSync(path, "utf8");
    for (const needle of needles) {
      if (content.includes(needle)) {
        throw new Error(`SECRET LEAK: a credential value appeared in ${path} — file NOT safe. Delete it.`);
      }
    }
    if (/sk-[A-Za-z0-9_-]{20,}/.test(content)) {
      throw new Error(`SECRET LEAK: sk- style key pattern found in ${path}.`);
    }
  }
}

// -------------------------------------------------------------------- main

async function main() {
  const personas = readdirSync(here)
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(readFileSync(join(here, f), "utf8")))
    .filter((p) => p?.id && p?.journey)
    .filter((p) => ONLY.length === 0 || ONLY.includes(p.id))
    .sort((a, b) => a.id.localeCompare(b.id));

  if (personas.length === 0) {
    console.error("No personas found. Persona files live next to this script as *.json with id + journey keys.");
    process.exit(1);
  }
  console.log(`Personas: ${personas.map((p) => p.id).join(", ")}${DRY_RUN ? "  [DRY RUN]" : ""}`);

  if (!DRY_RUN) {
    const health = await fetch(`${BASE}/health`).then((r) => r.json()).catch(() => null);
    if (!health?.ok || !health?.configured) {
      console.error(`Backend at ${BASE} is not up/configured. Start it: cd backend && npm start`);
      process.exit(1);
    }
  }
  if (!DRY_RUN && !SKIP_COMPLAINTS && !OPENAI_KEY) {
    console.error("OPENAI_API_KEY missing — run via: node --env-file=backend/.env harness/personas/run-personas.mjs");
    process.exit(1);
  }

  const stamp = `${fmtDate(new Date())}-${new Date().toTimeString().slice(0, 8).replaceAll(":", "")}`;
  const runDir = join(here, "runs", stamp);
  mkdirSync(runDir, { recursive: true });
  const written = [];
  const logOffset = backendLogSize();

  const journeys = [];
  for (const persona of personas) {
    const log = await runJourney(persona);
    journeys.push({ persona, log });
    const path = join(runDir, `${persona.id}.journey.json`);
    writeFileSync(path, JSON.stringify(log, null, 2));
    written.push(path);
  }

  const allComplaints = [];
  if (!DRY_RUN && !SKIP_COMPLAINTS) {
    for (const { persona, log } of journeys) {
      console.log(`\ncomplaints: ${persona.id}`);
      try {
        const feedback = await complaintsFor(persona, log);
        allComplaints.push({ persona: persona.id, name: persona.name, ...feedback });
        const path = join(runDir, `${persona.id}.complaints.json`);
        writeFileSync(path, JSON.stringify(feedback, null, 2));
        written.push(path);
      } catch (error) {
        console.error(`  complaint step failed for ${persona.id}: ${error.message}`);
      }
    }

    if (allComplaints.length > 0) {
      console.log("\ntriage: merging + ranking all complaints");
      try {
        const merged = await triage(allComplaints);
        const path = join(runDir, "triage.json");
        writeFileSync(path, JSON.stringify(merged, null, 2));
        written.push(path);
      } catch (error) {
        console.error(`  triage failed: ${error.message}`);
      }
    }
  }

  // Cost summary: backend [usage] lines added during this run + direct calls.
  const backendUsage = usageSince(logOffset);
  const directPrice = PRICING["gpt-4.1-mini"];
  const directCost = (directUsage.input * directPrice.input + directUsage.output * directPrice.output) / 1e6;
  const summary = {
    stamp, dryRun: DRY_RUN,
    personas: personas.map((p) => p.id),
    backendCalls: backendCallCount,
    backendUsage: backendUsage.byLabel,
    backendCostUSD: Number(backendUsage.cost.toFixed(4)),
    directCalls: directUsage.calls,
    directTokens: { input: directUsage.input, output: directUsage.output },
    directCostUSD: Number(directCost.toFixed(4)),
    totalCostUSD: Number((backendUsage.cost + directCost).toFixed(4))
  };
  const summaryPath = join(runDir, "summary.json");
  writeFileSync(summaryPath, JSON.stringify(summary, null, 2));
  written.push(summaryPath);

  assertNoSecrets(written);

  console.log("\n==== run summary ====");
  console.log(`backend calls: ${backendCallCount} — $${summary.backendCostUSD}`);
  for (const [label, u] of Object.entries(backendUsage.byLabel)) {
    console.log(`  ${label}: ${u.calls} calls, in=${u.input} out=${u.output}, $${u.cost.toFixed(4)}`);
  }
  console.log(`direct (persona/triage) calls: ${directUsage.calls} — $${summary.directCostUSD}`);
  console.log(`TOTAL measured spend: $${summary.totalCostUSD}`);
  console.log(`artifacts: ${runDir}`);
  console.log("secret scan: clean (no env values or sk- patterns in written files)");
}

main().catch((error) => {
  console.error(`FATAL: ${error.message}`);
  process.exit(1);
});
