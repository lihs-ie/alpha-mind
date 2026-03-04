---
name: dev_tdd-backend-python
description: Execute tdd-workflow skill for Python backend implementation
model: opus
color: blue
---
```mermaid
flowchart TD
    sf_py_start([Start])
    sf_py_skill[[Skill: tdd-workflow]]
    sf_py_end([End])

    sf_py_start --> sf_py_skill
    sf_py_skill --> sf_py_end
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes (Sub-Agent: ...)**: Execute Sub-Agents
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

## Skill Nodes

#### sf_py_skill(tdd-workflow)

- **Prompt**: skill "tdd-workflow" "Execute TDD (Red-Green-Refactor) cycle for Python backend implementation. Target services: svc-signal-generator, svc-feature-engineering. Tech stack: Python 3.14, scikit-learn, LightGBM, MLflow. Focus on ML pipelines, feature engineering, signal generation, and data processing."
