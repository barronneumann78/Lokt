#!/usr/bin/env node
// Logic check: Coach multi-draft path (owner ask 2026-09-23 — "one at a time
// is the default, but it should be able to do at least two if the person asks").
// Sibling of backend-sanitize-merge: the functions under test are EXTRACTED
// from the real backend/server.mjs at run time (brace-matched, never copied),
// so every assertion runs against the shipping code. Zero OpenAI cost.
//
// Guards proven here: single-draft shape unchanged, count cap, duplicate drop,
// every extra sanitized through the same pipeline, safety-branch contexts stay
// single, lineage fields describe the first draft only.
//
// Run: node harness/logic-checks/backend-coach-multi-draft/check.mjs
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

// --- Extract the real functions and consts (brace-matched) ------------------
// `bodyFrom` is where brace matching starts; for functions that is the end of
// the parameter list, so a destructured signature `({ a, b })` is skipped.
function extractBraced(startToken, name, bodyFrom = (start) => start) {
  const start = source.indexOf(startToken);
  if (start === -1) throw new Error(`${name} not found in backend/server.mjs`);
  let depth = 0;
  for (let i = source.indexOf("{", bodyFrom(start)); i < source.length; i += 1) {
    if (source[i] === "{") depth += 1;
    else if (source[i] === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(start, i + 1);
    }
  }
  throw new Error(`unbalanced braces extracting ${name}`);
}
function afterParameterList(start) {
  let depth = 0;
  for (let i = source.indexOf("(", start); i < source.length; i += 1) {
    if (source[i] === "(") depth += 1;
    else if (source[i] === ")") {
      depth -= 1;
      if (depth === 0) return i + 1;
    }
  }
  throw new Error("unbalanced parameter list");
}
const extractFunction = (name) => extractBraced(`function ${name}(`, `function ${name}`, afterParameterList);
const extractConst = (name) => `${extractBraced(`const ${name} = {`, `const ${name}`)};`;

const functionNames = [
  "clampNumber",
  "sanitizeRoutine",
  "sanitizeReply",
  "sanitizeCoachAction",
  "coachActionForContext",
  "sanitizeChangeSummary",
  "sanitizeOptionalRoutine",
  "sanitizeEditedRoutineID",
  "routineExerciseFacts",
  "computeRoutineDiffLine",
  "appendActualDiff",
  "normalizeCoachContext",
  "buildCoachChatResult",
  "coachMultiDraftAllowed",
  "coachDraftFingerprint",
  "sanitizeCoachDrafts"
];
const capConst = source.match(/^const maxCoachDrafts = \d+;$/m)?.[0];
check("maxCoachDrafts is a literal const in server.mjs", Boolean(capConst));

const logs = [];
const sandboxConsole = { log: (line) => logs.push(String(line)), warn: () => {}, error: () => {} };
const factory = new Function(
  "console",
  "catalogNameSet",
  "catalogEquipmentByName",
  [
    capConst,
    extractConst("workoutSchema"),
    extractConst("coachChatSchema"),
    ...functionNames.map(extractFunction),
    `return { maxCoachDrafts, workoutSchema, coachChatSchema, ${functionNames.join(", ")} };`
  ].join("\n\n")
);
const fns = factory(
  sandboxConsole,
  new Set(catalog.map((entry) => entry.name.toLowerCase())),
  new Map(catalog.map((entry) => [entry.name.toLowerCase(), entry.equipment]))
);

// --- Fixtures ---------------------------------------------------------------
const catalogName = catalog[0].name;
const exercise = (name, sets, reps, extra = {}) => ({
  name, sets, reps, notes: "", reasoning: "", tip: "", catalogMatch: true, ...extra
});
const routine = (title, exercises, extra = {}) => ({
  title, summary: `${title} summary`, rationale: "", routineNotes: [], exercises, ...extra
});
const legA = () => routine("Leg Day A", [exercise("Back Squat", 4, "5"), exercise("Romanian Deadlift", 3, "8")]);
const legB = () => routine("Leg Day B", [exercise("Front Squat", 4, "6"), exercise("Leg Press", 3, "12")]);
const pushDay = () => routine("Push Day", [exercise("Dumbbell Bench Press", 3, "8-10"), exercise("Lateral Raise", 3, "12-15")]);
const planning = fns.normalizeCoachContext({ kind: "planning", activeWorkout: null });
const draftEditing = fns.normalizeCoachContext({ kind: "draft_editing", activeWorkout: null });
const response = (overrides) => ({
  reply: "Here you go.",
  action: "created_draft",
  changeSummary: "Built what you asked for.",
  routine: legA(),
  editedRoutineID: null,
  additionalRoutines: [],
  ...overrides
});
const build = (overrides, context = planning, extra = {}) =>
  fns.buildCoachChatResult({ coachResponse: response(overrides), context, savedRoutines: [], currentRoutine: null, ...extra });

console.log("== backend-coach-multi-draft logic check ==");

// --- 0. Schema stays additive ----------------------------------------------
{
  const schema = fns.coachChatSchema;
  check("schema keeps every original required field",
    ["reply", "action", "changeSummary", "routine", "editedRoutineID"].every((key) => schema.required.includes(key)));
  check("schema requires additionalRoutines (strict mode lists every property)", schema.required.includes("additionalRoutines"));
  check("routine stays workoutSchema-or-null",
    JSON.stringify(schema.properties.routine) === JSON.stringify({ anyOf: [fns.workoutSchema, { type: "null" }] }));
  check("additionalRoutines is an array of workoutSchema capped at maxCoachDrafts - 1",
    schema.properties.additionalRoutines.type === "array" &&
      schema.properties.additionalRoutines.items === fns.workoutSchema &&
      schema.properties.additionalRoutines.maxItems === fns.maxCoachDrafts - 1);
  check("maxCoachDrafts is five (a training week)", fns.maxCoachDrafts === 5, `got ${fns.maxCoachDrafts}`);
}

// --- 1. Single-draft shape unchanged ----------------------------------------
{
  const out = build({});
  check("single draft: routine equals the same sanitizeRoutine output",
    JSON.stringify(out.routine) === JSON.stringify(fns.sanitizeRoutine(legA())));
  check("single draft: routines is null (older clients see no change)", out.routines === null);
  check("single draft: action/reply/changeSummary/editedRoutineID untouched",
    out.action === "created_draft" && out.reply === "Here you go." &&
      out.changeSummary === "Built what you asked for." && out.editedRoutineID === null);
  check("result carries exactly the six response keys",
    Object.keys(out).sort().join(",") === "action,changeSummary,editedRoutineID,reply,routine,routines");

  const legacy = fns.buildCoachChatResult({
    coachResponse: { reply: "r", action: "created_draft", changeSummary: null, routine: legA(), editedRoutineID: null },
    context: planning, savedRoutines: [], currentRoutine: null
  });
  check("a model reply without additionalRoutines still yields one draft", legacy.routine?.title === "Leg Day A" && legacy.routines === null);

  const replyOnly = build({ action: "reply_only", routine: null, additionalRoutines: [legB()] });
  check("reply_only never yields drafts even if extras are present", replyOnly.routine === null && replyOnly.routines === null && replyOnly.changeSummary === null);
}

// --- 2. Two drafts from one ask ---------------------------------------------
{
  const out = build({ additionalRoutines: [legB()] });
  check("two drafts: routines has both, in order", out.routines?.length === 2 && out.routines[1].title === "Leg Day B", `got ${out.routines?.length}`);
  check("two drafts: routines[0] is the very same object as routine", out.routines?.[0] === out.routine);
  check("two drafts: routine still describes the first draft", out.routine.title === "Leg Day A");

  const merged = build({ additionalRoutines: [routine("Leg Day B", [
    exercise("Front Squat", 1, "5 @ 70%"),
    exercise("Front Squat", 3, "5 @ 80%"),
    exercise("Bogus Machine Thing", 3, "10")
  ])] });
  const extra = merged.routines?.[1];
  check("extra draft goes through the same-name MERGE (sets sum, schemes join)",
    extra?.exercises.length === 2 && extra.exercises[0].sets === 4 && extra.exercises[0].reps === "1x5 @ 70%, 3x5 @ 80%",
    `got ${JSON.stringify(extra?.exercises?.[0])}`);
  check("extra draft gets catalogMatch recomputed server-side (model claim ignored)",
    extra?.exercises[1].catalogMatch === false);
  const catalogged = build({ additionalRoutines: [routine("B", [exercise(catalogName, 3, "10", { catalogMatch: false })])] });
  check("extra draft with a library name is marked catalogMatch true", catalogged.routines?.[1].exercises[0].catalogMatch === true);
  check("extra draft sets are clamped like the first",
    build({ additionalRoutines: [routine("B", [exercise("Leg Press", 40, "10")])] }).routines?.[1].exercises[0].sets === 10);
}

// --- 3. Deterministic guards: cap, duplicates, incomplete extras ------------
{
  logs.length = 0;
  const seven = Array.from({ length: 7 }, (_, i) => routine(`Day ${i + 2}`, [exercise(`Move ${i}`, 3, "10")]));
  const capped = build({ additionalRoutines: seven });
  check("count is capped at maxCoachDrafts", capped.routines?.length === fns.maxCoachDrafts, `got ${capped.routines?.length}`);
  check("cap drop is logged", logs.some((line) => line.includes("past the cap")));

  logs.length = 0;
  const sameAsA = routine("Leg Day A again", [exercise("back squat", 4, "5"), exercise("ROMANIAN DEADLIFT", 3, "8")]);
  const deduped = build({ additionalRoutines: [sameAsA, legB(), legB()] });
  check("exact-duplicate drafts are dropped (same exercises/sets/reps, title ignored, case-insensitive)",
    deduped.routines?.length === 2 && deduped.routines[1].title === "Leg Day B", `got ${deduped.routines?.map((r) => r.title).join(" | ")}`);
  check("duplicate drop is logged", logs.filter((line) => line.includes("dropped duplicate")).length === 2);

  const allDupes = build({ additionalRoutines: [sameAsA] });
  check("when every extra is a duplicate the reply collapses to a single draft", allDupes.routines === null && allDupes.routine.title === "Leg Day A");

  logs.length = 0;
  const broken = build({ additionalRoutines: [routine("", []), { title: "No exercises", exercises: [] }, legB()] });
  check("an incomplete extra is dropped, never fails the whole reply", broken.routines?.length === 2 && broken.routines[1].title === "Leg Day B");
  check("incomplete drop is logged", logs.filter((line) => line.includes("dropped incomplete")).length === 2);

  let threw = false;
  try { build({ routine: routine("", []) }); } catch { threw = true; }
  check("an incomplete FIRST draft still throws exactly as before", threw);

  const titled = build({ routine: routine("Leg Day", legA().exercises), additionalRoutines: [routine("Leg Day", legB().exercises), routine("leg day", pushDay().exercises)] });
  check("colliding titles are disambiguated for the routine library",
    titled.routines?.map((r) => r.title).join("|") === "Leg Day|Leg Day 2|leg day 3", `got ${titled.routines?.map((r) => r.title).join("|")}`);

  const promoted = build({ routine: null, additionalRoutines: [legA(), legB()] });
  check("a model that leaves routine null but fills extras still yields a first draft",
    promoted.routine?.title === "Leg Day A" && promoted.routines?.length === 2);
}

// --- 4. Safety branch and context guards ------------------------------------
{
  const checkIn = fns.normalizeCoachContext({
    kind: "active_workout",
    activeWorkout: { routineID: "1F6CBFD0-7C36-4A6E-A1C6-22E7BD4EBEFA", routineName: "Push", exercises: ["Bench Press"], checkInNote: "felt too hard; pain at Bench Press" }
  });
  const safety = build({ additionalRoutines: [legB()] }, checkIn);
  check("pain / needsRealCheckIn context never yields multiple drafts", safety.routines === null && safety.routine?.title === "Leg Day A");
  check("coachMultiDraftAllowed: planning + draft_editing only",
    fns.coachMultiDraftAllowed(planning) && fns.coachMultiDraftAllowed(draftEditing) &&
      !fns.coachMultiDraftAllowed(checkIn) && !fns.coachMultiDraftAllowed(fns.normalizeCoachContext({ kind: "routine_editing" })));

  const editing = build({ additionalRoutines: [legB()] }, fns.normalizeCoachContext({ kind: "routine_editing", activeWorkout: { routineName: "X", exercises: [] } }));
  check("routine editing context still yields no draft at all", editing.action === "suggestion" && editing.routine === null && editing.routines === null);

  const refining = build({ additionalRoutines: [legB()] }, draftEditing, { currentRoutine: pushDay() });
  check("refining a planning draft may still produce a set", refining.routines?.length === 2);
}

// --- 5. Lineage fields describe the FIRST draft only -------------------------
{
  const saved = [{ id: "A1B2C3D4-0000-0000-0000-000000000001", name: "Leg Day A", exercises: [{ name: "Back Squat", sets: 3, reps: "5" }] }];
  const out = fns.buildCoachChatResult({
    coachResponse: response({ action: "updated_draft", editedRoutineID: "a1b2c3d4-0000-0000-0000-000000000001", additionalRoutines: [legB()] }),
    context: planning, savedRoutines: saved, currentRoutine: null
  });
  check("editedRoutineID resolves against the saved list for the first draft", out.editedRoutineID === saved[0].id);
  check("server-computed diff is appended for the first draft", out.changeSummary.includes("Actual changes:") && out.changeSummary.includes("sets 3→4"), out.changeSummary);
  check("the second draft rides along as a brand-new routine", out.routines?.length === 2 && out.routines[1].title === "Leg Day B");
}

// --- 6. Wiring: handler, prompt, and chatWithCoach use the new seam ---------
{
  check("handler response emits routines additively", source.includes("routines: coachResult.routines,"));
  check("chatWithCoach delegates to buildCoachChatResult", extractFunction("chatWithCoach").includes("buildCoachChatResult({"));
  const instructions = source.slice(source.indexOf("const coachChatInstructions = ["), source.indexOf("].join", source.indexOf("const coachChatInstructions = [")));
  check("coach prompt includes the multi-draft block", instructions.includes("multiDraftInstructions"));
  const multi = source.slice(source.indexOf("const multiDraftInstructions = ["), source.indexOf("].join", source.indexOf("const multiDraftInstructions = [")));
  check("prompt keeps one draft as the default and asks a clarifying question only when unclear",
    multi.includes("One workout per reply is the default") && multi.includes("reply_only") && multi.includes("Never ask when the request is explicit"));
  check("generator/revision prompts are untouched by the multi-draft block",
    !source.slice(source.indexOf("const workoutGeneratorInstructions = ["), source.indexOf("const supplementaryWorkoutInstructions")).includes("multiDraftInstructions") &&
      !source.slice(source.indexOf("const workoutRevisionInstructions = ["), source.indexOf("const workoutNudgeInstructions")).includes("multiDraftInstructions"));
}

console.log(failures === 0 ? "BACKEND COACH MULTI-DRAFT CHECKS PASSED" : `${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
