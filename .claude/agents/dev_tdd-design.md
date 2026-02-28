---
name: dev_tdd-design
description: TDD (Red-Green-Refactor) cycle for design implementation
model: sonnet
---
```mermaid
flowchart TD
    des_sf_start([Start])
    des_sf_tdd_skill[[Skill: tdd-workflow]]
    des_sf_red[【TDD赤フェーズ】デザイン — 失敗するテストを書く]
    des_sf_green[【TDD緑フェーズ】デザイン — テストを通す最小限の実装]
    des_sf_refactor[【TDDリファクタリング】デザイン — コード整理]
    des_sf_end([End])

    des_sf_start --> des_sf_tdd_skill
    des_sf_tdd_skill --> des_sf_red
    des_sf_red --> des_sf_green
    des_sf_green --> des_sf_refactor
    des_sf_refactor --> des_sf_end
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes**: Execute Sub-Agents using the Task tool
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

## Skill Nodes

#### des_sf_tdd_skill(tdd-workflow)

- **Prompt**: skill "tdd-workflow" load-skill-knowledge-into-context-only

### Prompt Node Details

#### des_sf_red(【TDD赤フェーズ】デザイン — 失敗するテストを書く)

```
【TDD赤フェーズ】デザイン — 失敗するテストを書く
```

#### des_sf_green(【TDD緑フェーズ】デザイン — テストを通す最小限の実装)

```
【TDD緑フェーズ】デザイン — テストを通す最小限の実装
```

#### des_sf_refactor(【TDDリファクタリング】デザイン — コード整理)

```
【TDDリファクタリング】デザイン — コード整理
```
