# Recursive Meta Prompt Architecture

A Public Technical White Paper

Version 1.0
February 2026

## Abstract

This paper presents Recursive Meta Prompt Architecture, a deterministic pipeline for transforming informal human input into high compliance AI directives. The system rejects a single pass prompt pattern and replaces it with staged analysis, tier calibration, context fusion, and output enforcement. The result is stronger directive precision, lower verbosity drift, and better alignment between input complexity and output structure.

## 1. Introduction

Modern language models reward clarity, explicit scope, and concrete constraints. Human inputs, however, often contain emotional noise, vague verbs, and implicit context. A direct rewrite model cannot reliably close this gap. It either over structures simple requests or under structures complex requests.

Recursive Meta Prompt Architecture addresses this failure by separating understanding from generation. It builds an intermediate representation of user intent and entity context before any prompt assembly occurs.

## 2. Problem Statement

A single pass optimizer faces three recurrent failure classes.

1. Verbosity bias
Simple user input expands into long output with low information density.

2. Recency bias
Late prompt tokens overpower early constraints in long system instructions.

3. Context dilution
Global context and style language can contaminate task specific interpretation.

The architectural objective is to maximize directive force per word while preserving full user intent.

## 3. Design Principles

1. Complexity should come from task load, not from template habit.
2. Emotional signal should affect urgency wording, not task tier.
3. Context should increase specificity, not document length.
4. Every stage should be auditable and deterministic where possible.
5. Enforcement should include both generation time constraints and post generation cleanup.

## 4. System Overview

The runtime pipeline has seven ordered steps.

1. Intent Decomposer
Consumes raw input and returns intents, intent count, urgency level, emotional markers, cleaned input, and raw input.

2. Entity Extractor
Finds persons, projects, environments, technical terms, temporal markers, and organizations from raw text only.

3. Complexity Classifier
Computes ambiguity score and maps input to one of four tiers.

4. Context Engine
Retrieves nearest semantic matches and builds a compact context block.

5. Prompt Assembler
Injects tier calibration, max output word budget, context block, and tier matched examples into the system message.

6. Model Execution
Runs the provider call with assembled system and user messages.

7. Post Processor
Applies structural cleanup and meta leakage suppression, and triggers compression fallback when required.

## 5. Intent Decomposition

Intent decomposition uses lexical tagging to pair verbs with nearby objects. Compound requests are segmented across conjunction patterns so each action is represented independently.

Example
Input: fix login bug and add logging and update docs
Output intents:
1. fix login bug
2. add logging
3. update docs

Urgency markers are collected separately. This allows urgency reflection in final wording without corrupting complexity assessment.

## 6. Entity Extraction

Entity extraction operates before prompt assembly so that only raw user data drives entity memory. The extractor records:

1. persons
2. projects
3. environments
4. technical terms
5. temporal markers
6. organizations

Structured tags are stored with context entries. Cluster naming then uses entity frequency instead of noisy text fragments.

## 7. Complexity Classification

Tier assignment is based on intent count, ambiguity score, and multi system detection.

1. Tier 1 surgical
Single intent with low ambiguity.

2. Tier 2 focused
Two intents or one intent with moderate ambiguity.

3. Tier 3 structured
Three to four intents or elevated ambiguity.

4. Tier 4 architectural
Five or more intents, high ambiguity, or explicit multi system scope.

Word budgets scale by tier and input length. This constrains output growth while preserving sufficient detail for complex tasks.

## 8. Context Memory and Naming

The context engine stores input embedding and output embedding separately, with structured entity metadata. Stop phrase filtering removes control language fragments before embedding and term extraction.

Cluster names follow entity first naming logic:

1. most frequent project entity
2. most frequent environment entity
3. combined display label in compact form

This yields stable names tied to user work context instead of internal instruction artifacts.

## 9. Prompt Assembly

System prompt construction follows a fixed architecture:

1. role anchor
2. tier calibration
3. forbidden constraints
4. transformation rules
5. learned context injection
6. tier matched examples
7. self verification checklist

The assembler also injects anti meta leakage language so the final model output reads as direct expert instruction, not process commentary.

## 10. Post Processing and Enforcement

Post processing protects output quality when generation drifts.

1. Word budget enforcement
If Tier 1 or Tier 2 output exceeds budget by a large margin, the interface exposes a compression action.

2. Structural enforcement for simple tier
Headers, list markers, and bold markers are removed and merged into plain prose.

3. Meta leakage defense
Self referential lines are removed. Excessive leakage triggers controlled retry with a strict output only directive.

## 11. Security and Reliability Notes

1. API credentials remain in platform secure storage.
2. Context migration preserves existing data where schema changes permit it.
3. Structured metadata and analytics support deterministic regression testing.

## 12. Expected Outcomes

Recursive Meta Prompt Architecture is designed to produce measurable improvements in:

1. output length proportionality
2. structural correctness for simple tasks
3. context grounded specificity
4. reduction of meta commentary leakage
5. consistency across provider backends

## 13. Conclusion

Prompt optimization quality is an architecture problem before it is a wording problem. Recursive Meta Prompt Architecture resolves this by separating intent analysis, entity memory, complexity calibration, context fusion, and enforcement into explicit stages. The architecture closes the gap between informal human input and high precision model directives while keeping output tightly coupled to real task complexity.
