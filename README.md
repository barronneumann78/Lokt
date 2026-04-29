# Lokt

Lokt is an AI workout coach that turns conversation into training.

Instead of forcing users through rigid forms, Lokt lets them ask for a workout in plain English, speak it out loud, import a plan from a photo, refine it through coach-style chat, and then log the session quickly once they start lifting.

## Preview

![Lokt coach preview](/Users/barronneumann/Desktop/Locked%20In%20Set%20Tracker/submission/assets/lokt-coach-preview.png)

## The Pitch

Text your workout coach. Lokt can build a routine, revise it, explain it, and keep the final draft structured and reviewable before anything is saved.

## What It Does

- Generates editable workout drafts from natural-language prompts
- Imports workouts from voice notes and photos
- Keeps a coach-style chat available for follow-up questions and workout changes
- Suggests contextual exercise swaps and add-on blocks
- Supports manual routine building alongside AI flows
- Makes workout logging faster with quick set entry, rest timers, and guided flow
- Tracks workout history and analytics

## Why I Built It

Most workout apps are either good at tracking or good at giving advice, but they still make planning feel manual and fragmented. I wanted to build something that feels more like texting a smart coach who can actually do something for you.

## How I Built It

Lokt is built as a SwiftUI iPhone app with a lightweight Node backend for AI routes. I used Codex heavily to help design and implement the product flow, structured AI parsing, import reviews, coach chat, exercise metadata handling, and UI polish across the app.

## Core AI Flows

### Ask Lokt
Users can describe a workout like:

`Make me a 45-minute dumbbell-only push day`

Lokt returns a structured, editable routine draft instead of generic freeform advice.

### Voice Import
Users can speak a list of exercises or describe the session they want. Lokt transcribes the audio, matches exercises, and shows a review screen before anything is saved.

### Photo Import
Users can upload a screenshot or photo of a routine sheet, notes app plan, or handwritten workout. Lokt extracts the structure, matches exercises, and turns it into a clean draft.

### Coach Chat
Lokt can answer normal training questions, explain choices, suggest substitutions, or update a workout draft when the user is actually asking for a change.

## Stack

- SwiftUI
- Node.js backend
- OpenAI-powered workout generation, revision, transcription, and parsing routes
- Structured JSON draft/review flows

## Repository Notes

This repo contains both the iOS app and the backend used for AI-assisted features. The app keeps review-before-save in place so AI outputs do not silently become routines without user confirmation.

## Contest Submission Assets

Prepared contest materials live in:

- [submission/handshake-entry.md](/Users/barronneumann/Desktop/Locked%20In%20Set%20Tracker/submission/handshake-entry.md)
- [showcase/index.html](/Users/barronneumann/Desktop/Locked%20In%20Set%20Tracker/showcase/index.html)
- [submission/assets/lokt-home-preview.png](/Users/barronneumann/Desktop/Locked%20In%20Set%20Tracker/submission/assets/lokt-home-preview.png)
