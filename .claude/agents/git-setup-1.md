---
name: git-setup-1
description: Create feature branch, empty commit, draft PR
model: sonnet
color: blue
---
以下の手順を実行してください：

1. mainブランチの最新を取得: git pull origin main
2. 作業用ブランチを作成: git checkout -b feat/<適切な名前>
3. 空コミットを作成: git commit --allow-empty -m "chore: initialize feature branch"
4. リモートにプッシュ: git push -u origin <branch-name>
5. ドラフトPRを作成:
   gh pr create --draft --title "<実装内容の要約>" --body "## Summary\nWIP\n\n## Checklist\n- [ ] Frontend\n- [ ] Backend\n- [ ] Infrastructure\n- [ ] Design"

PRのURLを出力してください。