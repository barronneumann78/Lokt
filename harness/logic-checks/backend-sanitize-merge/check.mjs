#!/usr/bin/env node
// Logic check: sanitizeRoutine same-name MERGE + the under-duration post-check
// (persona report 2026-09-01 NEW-1). The Swift logic-checks convention compiles
// the REAL app sources; this is the backend equivalent — the functions under
// test are EXTRACTED from backend/server.mjs at run time (never copied), so the
// assertions always run against the shipping code. Zero OpenAI cost.
//
// Run: node harness/logic-checks/backend-sanitize-merge/check.mjs
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const source = readFileSync(path.join(repoRoot, "backend", "server.mjs"), "utf8");
const catalog = JSON.parse(readFileSync(path.join(repoRoot, "backend", "exercise-catalog.json"), "utf8"));

let failures = 0;
function check(label, condition, detail = "") {
  if (condition) console.log(`  PASS  ${label}`);
  else { console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ""}`); failures += 1; }
}

// --- Extract the real functions (brace-matched, not regex-bodied) -----------
function extractFunction(name) {
  const start = source.indexOf(`function ${name}(`);
  if (start === -1) throw new Error(`function ${name} not found in backend/server.mjs`);
  let depth = 0;
  for (let i = source.indexOf("{", start); i < source.length; i += 1) {
    if (source[i] === "{") depth += 1;
    else if (source[i] === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(start, i + 1);
    }
  }
  throw new Error(`unbalanced braces extracting ${name}`);
}

const functionNames = [
  "clampNumber",
  "sanitizeRoutine",
  "statedTimeLimitMinutes",
  "effectiveTimeLimitMinutes",
  "parseSecondsFromText",
  "statedRestSeconds",
  "workSecondsPerSet",
  "guessedRestSeconds",
  "estimateRoutineMinutes",
  "routinePostCheckIssues",
  "retitleForHonestDuration",
  "preferredEquipmentSet",
  "normalizePreferences",
  "formatPreferences",
  "normalizeCoachContext",
  "formatCoachContext",
  "sanitizeCoachAction",
  "coachActionForContext"
];
const estimatorConsts = (source.match(/^const estimator\w+ = \d+;$/gm) ?? []).join("\n");
const equipmentAliasPairs = extractFunction("preferredEquipmentSet").includes("equipmentAliasPairs")
  ? source.slice(source.indexOf("const equipmentAliasPairs"), source.indexOf("];", source.indexOf("const equipmentAliasPairs")) + 2)
  : "";

const logs = [];
const sandboxConsole = { log: (line) => logs.push(String(line)), warn: () => {}, error: () => {} };
const factory = new Function(
  "console",
  "catalogNameSet",
  "catalogEquipmentByName",
  [
    estimatorConsts,
    equipmentAliasPairs,
    ...functionNames.map(extractFunction),
    `return { ${functionNames.join(", ")} };`
  ].join("\n\n")
);
const fns = factory(
  sandboxConsole,
  new Set(catalog.map((entry) => entry.name.toLowerCase())),
  new Map(catalog.map((entry) => [entry.name.toLowerCase(), entry.equipment]))
);

const exercise = (name, sets, reps, extra = {}) => ({
  name, sets, reps, notes: "", reasoning: "", tip: "", ...extra
});
const routineWith = (exercises) => ({ title: "Test Routine", summary: "s", rationale: "", routineNotes: [], exercises });

console.log("== backend-sanitize-merge logic check ==");

// --- 0. Safety-aware preference profile (backward-compatible normalization) --
{
  const normalized = fns.normalizePreferences({
    preferredEquipment: ["Dumbbells"],
    trainingExperience: "returning_to_training",
    age: 36,
    injuryFlags: ["shoulder", "knee", "shoulder", "made_up_flag"]
  });
  check("safe profile keeps a recognized training experience", normalized.trainingExperience === "returning_to_training");
  check("safe profile keeps a plausible age", normalized.age === 36);
  check("safe profile keeps only unique recognized injury flags", normalized.injuryFlags.join(",") === "shoulder,knee");

  const legacy = fns.normalizePreferences({ preferredEquipment: ["Bands"] });
  check(
    "legacy preference payload remains valid without safe-profile fields",
    legacy.trainingExperience === "" && legacy.age === null && legacy.injuryFlags.length === 0
  );

  const invalid = fns.normalizePreferences({
    trainingExperience: "advanced",
    age: 121,
    injuryFlags: ["unknown"]
  });
  check(
    "safe profile rejects unknown experience, invalid age, and unknown flags",
    invalid.trainingExperience === "" && invalid.age === null && invalid.injuryFlags.length === 0
  );

  const profileText = fns.formatPreferences(normalized);
  check(
    "formatted profile carries experience, age, and flagged areas to every AI prompt",
    profileText.includes("Training experience: returning to training") &&
      profileText.includes("Age: 36") &&
      profileText.includes("Areas to work around: shoulder, knee")
  );
}

// --- 1. Frank's percent ramp survives as one merged multi-scheme entry ------
{
  const out = fns.sanitizeRoutine(routineWith([
    exercise("Barbell back squat", 1, "5 @ 70% 1RM", { tip: "Rest 3-4 minutes after this set before next work set" }),
    exercise("Barbell back squat", 1, "3 @ 80% 1RM"),
    exercise("Barbell back squat", 1, "1 @ 90% 1RM"),
    exercise("Barbell back squat", 3, "5 @ 75% 1RM", { notes: "Backoff work" }),
    exercise("Romanian Deadlift", 3, "8")
  ]));
  check("Frank ramp: 5 entries merge to 2 exercises", out.exercises.length === 2, `got ${out.exercises.length}`);
  const squat = out.exercises[0];
  check("Frank ramp: squat keeps first position", squat.name === "Barbell back squat");
  check("Frank ramp: sets sum to 6", squat.sets === 6, `got ${squat.sets}`);
  check(
    "Frank ramp: reps joins every scheme in order",
    squat.reps === "1x5 @ 70% 1RM, 1x3 @ 80% 1RM, 1x1 @ 90% 1RM, 3x5 @ 75% 1RM",
    `got "${squat.reps}"`
  );
  check("Frank ramp: backoff note survives the merge", squat.notes.includes("Backoff work"));
  check("Frank ramp: 'next work set' tip is no longer a lie", squat.tip.includes("next work set") && squat.sets > 1);
  check("Frank ramp: RDL untouched", out.exercises[1].name === "Romanian Deadlift" && out.exercises[1].reps === "8");
  check("merge is logged as [sanitize] merged", logs.some((line) => line.includes('[sanitize] merged duplicate exercise "Barbell back squat"')));
  check("nothing is logged as dropped", !logs.some((line) => line.includes("dropped duplicate")));
}

// --- 1a. Routine-editor Coach context stays whole-workout and advice-only ---
{
  const context = fns.normalizeCoachContext({
    kind: "routine_editing",
    activeWorkout: {
      routineID: "1F6CBFD0-7C36-4A6E-A1C6-22E7BD4EBEFA",
      routineName: "Thursday Push",
      exercises: ["Bench Press", "Seated Dumbbell Shoulder Press"],
      nextExercise: "This must not be treated as active"
    }
  });
  const rendered = fns.formatCoachContext(context);
  check("routine editor Coach context is preserved", context.kind === "routine_editing");
  check(
    "routine editor Coach context carries the in-progress exercise list",
    rendered.includes("Routine editing") &&
      rendered.includes("Thursday Push") &&
      rendered.includes("Bench Press")
  );
  check(
    "routine editor Coach context does not present an active-workout next exercise",
    !rendered.includes("This must not be treated as active")
  );
  check(
    "routine editor Coach context cannot produce a draft",
    fns.coachActionForContext("updated_draft", context) === "suggestion" &&
      fns.coachActionForContext("created_draft", context) === "suggestion"
  );
}

// --- 2. Dana's "second lighter round" merges instead of dropping ------------
{
  const out = fns.sanitizeRoutine(routineWith([
    exercise("Seated Leg Curl", 3, "12"),
    exercise("Seated Leg Curl", 2, "12", { notes: "Second lighter round" }),
    exercise("Leg Press", 3, "10")
  ]));
  const curl = out.exercises[0];
  check("Dana: same-reps dupes merge to one entry", out.exercises.length === 2);
  check("Dana: sets sum (3+2=5)", curl.sets === 5, `got ${curl.sets}`);
  check("Dana: identical reps stay a single scheme text", curl.reps === "12", `got "${curl.reps}"`);
  check("Dana: lighter-round note kept", curl.notes.includes("Second lighter round"));
}

// --- 3. Merge mechanics: case-insensitivity, coalescing, caps, no-op --------
{
  const out = fns.sanitizeRoutine(routineWith([
    exercise("bench press", 2, "5"),
    exercise("Bench Press", 2, "5")
  ]));
  check("case-insensitive names merge", out.exercises.length === 1 && out.exercises[0].sets === 4);

  const split = fns.sanitizeRoutine(routineWith([
    exercise("Deadlift", 1, "5 @ 75%"),
    exercise("Deadlift", 1, "5 @ 75%"),
    exercise("Deadlift", 1, "5 @ 75%")
  ]));
  check("adjacent identical schemes coalesce (no 1x spam)", split.exercises[0].reps === "5 @ 75%" && split.exercises[0].sets === 3,
    `got sets ${split.exercises[0].sets}, reps "${split.exercises[0].reps}"`);

  const capped = fns.sanitizeRoutine(routineWith([
    exercise("Squat", 8, "5"),
    exercise("Squat", 8, "3")
  ]));
  check("merged sets stay capped at 10", capped.exercises[0].sets === 10, `got ${capped.exercises[0].sets}`);

  const clean = fns.sanitizeRoutine(routineWith([
    exercise("Squat", 3, "5"),
    exercise("Bench Press", 3, "8")
  ]));
  check("no-dupe routine passes through unchanged", clean.exercises.length === 2 && clean.exercises[0].reps === "5" && clean.exercises[1].reps === "8");

  const tips = fns.sanitizeRoutine(routineWith([
    exercise("Squat", 1, "5", { tip: "Brace hard.", reasoning: "Main lift" }),
    exercise("Squat", 3, "8", { tip: "Brace hard.", reasoning: "Volume driver" })
  ]));
  check("identical tips are not duplicated", tips.exercises[0].tip === "Brace hard.", `got "${tips.exercises[0].tip}"`);
  check("first non-empty reasoning wins", tips.exercises[0].reasoning === "Main lift");
}

// --- 4. Under-duration post-check (NEW-1's second half) ---------------------
{
  const tiny = routineWith([exercise("Plank", 1, "60 sec", { tip: "Rest 45 seconds" })]);
  const issues = fns.routinePostCheckIssues(tiny, 90, {}, true);
  const timeIssue = issues.find((issue) => issue.kind === "time");
  check("under-filled 90-min request raises a time issue", Boolean(timeIssue));
  check("under-fill issue carries the estimate", Boolean(timeIssue) && timeIssue.estimatedMinutes < 90 * 0.4);
  check("under-fill feedback names both numbers", Boolean(timeIssue) && timeIssue.feedback.includes("90 minutes") && /about \d+ minutes/.test(timeIssue.feedback));
  check("under-fill log says under-filled", Boolean(timeIssue) && timeIssue.log.includes("under-filled"));

  const prefOnly = fns.routinePostCheckIssues(tiny, 90, {}, false);
  check("preference-only limit does NOT trip the under check", !prefOnly.some((issue) => issue.kind === "time"));

  const big = routineWith(Array.from({ length: 8 }, (_, i) => exercise(`Move ${i}`, 4, "10", { tip: "Rest 90 seconds" })));
  const over = fns.routinePostCheckIssues(big, 30, {}, true);
  check("over-limit check still fires (regression guard)", over.some((issue) => issue.kind === "time" && issue.log.includes("work sets")));

  const inBand = routineWith(Array.from({ length: 4 }, (_, i) => exercise(`Move ${i}`, 3, "10", { tip: "Rest 60 seconds" })));
  const quiet = fns.routinePostCheckIssues(inBand, 30, {}, true);
  check("in-band estimate raises no time issue", !quiet.some((issue) => issue.kind === "time"));
}

// --- 5. Honest retitle works downward too -----------------------------------
{
  const retitled = fns.retitleForHonestDuration(
    { title: "90-Minute Squat Day", summary: "A dense 90 minutes of squatting.", exercises: [] },
    90,
    9.8
  );
  check("under-filled title retitles honestly (90 -> 10)", retitled.title === "10-Minute Squat Day", `got "${retitled.title}"`);
  check("summary retitles too", retitled.summary.includes("about 10 minutes"), `got "${retitled.summary}"`);
}

// --- 6. Stated-vs-preference limit split ------------------------------------
{
  check("statedTimeLimitMinutes reads '90-minute session'", fns.statedTimeLimitMinutes("Powerlifting, 90-minute session") === 90);
  check("statedTimeLimitMinutes null without a duration", fns.statedTimeLimitMinutes("quick pump for arms") === null);
  check("effectiveTimeLimitMinutes falls back to preference", fns.effectiveTimeLimitMinutes("quick pump", { defaultTimeLimitMinutes: 45 }) === 45);
  check("prompt-stated limit beats preference", fns.effectiveTimeLimitMinutes("30 minutes only", { defaultTimeLimitMinutes: 45 }) === 30);
}

console.log(failures === 0 ? "BACKEND SANITIZE-MERGE CHECKS PASSED" : `${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
