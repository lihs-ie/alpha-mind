---
name: dev_tdd-infrastructure
description: Execute tdd-workflow skill for infrastructure implementation
model: opus
color: green
---
```mermaid
flowchart TD
    sf_infra_start([Start])
    sf_infra_skill[[Skill: tdd-workflow]]
    sf_infra_end([End])

    sf_infra_start --> sf_infra_skill
    sf_infra_skill --> sf_infra_end
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes (Sub-Agent: ...)**: Execute Sub-Agents
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

## Skill Nodes

#### sf_infra_skill(tdd-workflow)

- **Prompt**: skill "tdd-workflow" "Execute TDD (Red-Green-Refactor) cycle for infrastructure implementation. Focus on Terraform modules, CI/CD pipelines, cloud resources, and deployment configuration."
