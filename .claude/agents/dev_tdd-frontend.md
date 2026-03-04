---
name: dev_tdd-frontend
description: Execute tdd-workflow skill for frontend implementation
model: opus
color: red
---
```mermaid
flowchart TD
    sf_fe_start([Start])
    sf_fe_skill[[Skill: tdd-workflow]]
    sf_fe_end([End])

    sf_fe_start --> sf_fe_skill
    sf_fe_skill --> sf_fe_end
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes (Sub-Agent: ...)**: Execute Sub-Agents
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

## Skill Nodes

#### sf_fe_skill(tdd-workflow)

- **Prompt**: skill "tdd-workflow" "Execute TDD (Red-Green-Refactor) cycle for frontend implementation. Focus on UI components, client-side logic, routing, and state management."
