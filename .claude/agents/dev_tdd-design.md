---
name: dev_tdd-design
description: Execute tdd-workflow skill for design implementation
model: sonnet
color: yellow
---
```mermaid
flowchart TD
    sf_design_start([Start])
    sf_design_skill[[Skill: tdd-workflow]]
    sf_design_end([End])

    sf_design_start --> sf_design_skill
    sf_design_skill --> sf_design_end
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes (Sub-Agent: ...)**: Execute Sub-Agents
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

## Skill Nodes

#### sf_design_skill(tdd-workflow)

- **Prompt**: skill "tdd-workflow" "Execute TDD (Red-Green-Refactor) cycle for design system implementation. Focus on design system tokens, component styles, theming, and visual consistency. Red: Write failing tests. Green: Implement minimum code to pass. Refactor: Clean up while keeping tests green."
