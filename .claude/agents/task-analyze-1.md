---
name: task-analyze-1
description: Understand requirements and decompose into domain tasks
model: opus
---
Phase 1 - Task Understanding: Read and analyze all relevant project documentation to understand the requirements, architecture, and constraints. Review CLAUDE.md, design documents, and any referenced specification files to build comprehensive context for the task.

Phase 2 - Task Decomposition: Decompose the task into subtasks and determine which domains (Frontend, Backend, Infrastructure, Design) need work. If only one domain is affected, route to that domain's solo branch. If multiple domains are affected, route to the default branch for parallel execution across all domains.