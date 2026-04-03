# KscTool dotfiles

공유 가능한 shell 설정 파일들. 개인정보 없음.

## 파일 구성

| 파일 | 설명 |
|------|------|
| `.bash_aliases` | 경로 이동 alias, 프로젝트 단축키 |
| `.bash_functions` | 함수 모음 (fzf, 파일 전송, 빌드 헬퍼 등) |
| `.bashrc` | 환경변수, NVM, 프로젝트 설정 |

## 개인정보 분리 구조

민감 정보(`ROOT_PW`, API 키, 이메일)는 `~/.private/`에 별도 보관.  
`.bashrc` 시작 시 `~/.private/*.sh`를 자동 source.

```
~/.private/          ← gitignore, 공유 X
├── secrets.sh       ← GEMINI_API_KEY, ROOT_PW
└── accounts.sh      ← CLAUDE_TEAM_EMAIL, CLAUDE_PERSONAL_EMAIL
```

## 설치

```bash
cp .bash_aliases ~/.bash_aliases
cp .bash_functions ~/.bash_functions
cp .bashrc ~/.bashrc
mkdir -m 700 ~/.private
# ~/.private/secrets.sh, accounts.sh 직접 작성 (본인 값으로)
source ~/.bashrc
```
