---
description: 要件理解からドメイン別実装・レビュー・デプロイまで自動化するAI駆動の完全開発ワークフロー
---
```mermaid
flowchart TD
    start_1([Start])
    git_setup_1[git-setup-1]
    task_understand_1[task-understand-1]
    task_decompose_1[task-decompose-1]
    domain_switch_1{Switch:<br/>Conditional Branch}
    fe_eng_solo[["fe-eng-solo"]]
    fe_rev_solo[fe-rev-solo]
    be_eng_solo[["be-eng-solo"]]
    be_rev_solo[be-rev-solo]
    infra_eng_solo[["infra-eng-solo"]]
    infra_rev_solo[infra-rev-solo]
    designer_solo[["designer-solo"]]
    design_rev_solo[design-rev-solo]
    task_distributor_1[task-distributor-1]
    fe_eng_all[["fe-eng-all"]]
    be_eng_all[["be-eng-all"]]
    infra_eng_all[["infra-eng-all"]]
    designer_all[["designer-all"]]
    fe_rev_all[fe-rev-all]
    be_rev_all[be-rev-all]
    infra_rev_all[infra-rev-all]
    design_rev_all[design-rev-all]
    git_finalize_1[git-finalize-1]
    end_1([End])

    start_1 --> git_setup_1
    git_setup_1 --> task_understand_1
    task_understand_1 --> task_decompose_1
    task_decompose_1 --> domain_switch_1
    domain_switch_1 -->|Frontend| fe_eng_solo
    domain_switch_1 -->|Backend| be_eng_solo
    domain_switch_1 -->|Infrastructure| infra_eng_solo
    domain_switch_1 -->|Design| designer_solo
    domain_switch_1 -->|default| task_distributor_1
    fe_eng_solo --> fe_rev_solo
    be_eng_solo --> be_rev_solo
    infra_eng_solo --> infra_rev_solo
    designer_solo --> design_rev_solo
    task_distributor_1 --> fe_eng_all
    task_distributor_1 --> be_eng_all
    task_distributor_1 --> infra_eng_all
    task_distributor_1 --> designer_all
    fe_eng_all --> fe_rev_all
    be_eng_all --> be_rev_all
    infra_eng_all --> infra_rev_all
    designer_all --> design_rev_all
    fe_rev_solo --> git_finalize_1
    be_rev_solo --> git_finalize_1
    infra_rev_solo --> git_finalize_1
    design_rev_solo --> git_finalize_1
    fe_rev_all --> git_finalize_1
    be_rev_all --> git_finalize_1
    infra_rev_all --> git_finalize_1
    design_rev_all --> git_finalize_1
    git_finalize_1 --> end_1
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes**: Execute Sub-Agents using the Task tool
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

## Sub-Agent Flow Nodes

#### fe_eng_solo(TDD-Frontend-Solo)

@Sub-Agent: dev_tdd-frontend

#### be_eng_solo(TDD-Backend-Solo)

@Sub-Agent: dev_tdd-backend

#### infra_eng_solo(TDD-Infra-Solo)

@Sub-Agent: dev_tdd-infrastructure

#### designer_solo(TDD-Design-Solo)

@Sub-Agent: dev_tdd-design

#### fe_eng_all(TDD-Frontend-All)

@Sub-Agent: dev_tdd-frontend

#### be_eng_all(TDD-Backend-All)

@Sub-Agent: dev_tdd-backend

#### infra_eng_all(TDD-Infra-All)

@Sub-Agent: dev_tdd-infrastructure

#### designer_all(TDD-Design-All)

@Sub-Agent: dev_tdd-design

### Switch Node Details

#### domain_switch_1(Multiple Branch (2-N))

**Evaluation Target**: Task decomposition routing result: which domains need work

**Branch conditions:**
- **Frontend**: Only frontend changes needed
- **Backend**: Only backend changes needed
- **Infrastructure**: Only infrastructure changes needed
- **Design**: Only design changes needed
- **default**: Other cases

**Execution method**: Evaluate the results of the previous processing and automatically select the appropriate branch based on the conditions above.
