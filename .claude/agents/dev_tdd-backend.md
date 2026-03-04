---
name: dev_tdd-backend
description: Execute tdd-workflow skill for backend implementation
model: sonnet
color: blue
---
```mermaid
flowchart TD
    sf_be_start([Start])
    sf_be_skill[[Skill: tdd-workflow]]
    sf_be_end([End])

    sf_be_start --> sf_be_skill
    sf_be_skill --> sf_be_end
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes (Sub-Agent: ...)**: Execute Sub-Agents
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

## Skill Nodes

#### sf_be_skill(tdd-workflow)

- **Prompt**: skill "tdd-workflow" "Execute TDD (Red-Green-Refactor) cycle for backend implementation. Focus on API endpoints, business logic, data access, and service layer. Red: Write failing tests. Green: Implement minimum code to pass. Refactor: Clean up while keeping tests green."
