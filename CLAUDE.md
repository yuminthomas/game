# 크로놀리스 (CHRONOLITH) — 작업 안내

탑뷰 2D 픽셀 액션 RPG. Godot 4.3, GDScript, 내부 해상도 640×360(정수배 확대, nearest), 60fps, GL Compatibility 렌더러(웹 내보내기용).

## 먼저 읽을 것
1. `docs/GDD.md` — 기획서 텍스트 사본. 수치가 애매하면 원본 `docs/GDD.pdf` 가 기준이다.
2. `docs/PROGRESS.md` — 단계별 진행, **기획서에 없어서 정한 값(decided)**, 기획서와 다르게 한 부분, 남은 문제.
3. `docs/ASSETS.md` — 스프라이트 규격과 교체 규칙.

## 규칙
- **기획서 수치는 임의로 바꾸지 않는다.** 바꿔야 하면 이유를 `docs/PROGRESS.md` 에 적는다.
- 기획서에 없는 판단은 분위기에 맞게 정하고 `docs/PROGRESS.md` 의 "정한 값" 표에 기록한다. 데이터 파일에는 `(decided)` 주석을 남긴다.
- **수치는 코드에 쓰지 않는다.** 조작감·공식·계수는 `data/balance.json`, 무기군 특성은 `data/weapon_classes.json`, 무기·스킬·아이템은 각 json. 코드는 `Data.bal("control.dash.speed")` 처럼 꺼내 쓴다.
- 게임 로직과 화면 표시를 분리한다 (`PlayerData` 는 노드가 아닌 순수 데이터).
- 모든 플레이어 피해는 `Player.deal()` → `Combatant.take_hit()` → `Combat.compute()` 를 지난다.
- 시간은 `delta` 대신 `Clock.dt(delta, is_player)` (히트스톱·저스트 회피 슬로우·시간 정지 반영).
- 주석·커밋 메시지·문서는 한국어.
- 작업은 작은 단위로 나눠 단위마다 커밋한다.

## 폴더
```
autoload/      전역: Data(데이터 로더·검증) Text Settings InputManager Clock Game Fx DebugConsole
data/          balance, weapon_classes, grades, weapons(54), skills(54), status_effects, items, monsters, text_ko
scripts/core/  PlayerData(스탯·인벤토리·스킬), Items(아이템 인스턴스·옵션·툴팁), SpriteFactory(그래픽 공급·임시 도트), FxLayer
scripts/combat/ HitInfo, Combat(피해 공식·판정 도형), Combatant, StatusSet, Projectile, Zone
scripts/player/ Player(상태 머신·방어·기력·고유 효과), PlayerAttacks(콤보·차지·대시 공격), LayeredCharacter(레이어 스프라이트)
scripts/skills/ SkillExecutor(시전 조건·공용 연출), SkillRun(동작 유형 28종), GhostActor(크로노 '잔상')
scripts/enemies/ Enemy(허수아비·테스트 몬스터 AI)
scripts/world/ TestZone, ZoneGround, GameCamera, LootDrop
scripts/ui/    UIRoot, HUD, GameWindow(드래그·위치 저장), SlotBox, 각 창, SkillbookPicker, PauseMenu, UITheme
tests/         run_tests(자동 테스트), screenshots(화면 캡처)
play/          웹 빌드 결과물 (GitHub Pages 에서 /play/ 로 열림). Godot 가 읽지 않도록 .gdignore 가 있다
```

## 실행·검증
Godot 4.3 실행 파일을 `godot` 라고 할 때:
```bash
godot --path .                                         # 게임 실행
godot --headless --path . res://tests/run_tests.tscn   # 자동 테스트 (끝에 "결과: N 통과, 0 실패")
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 640x360 res://tests/screenshots.tscn -- /tmp/shots   # 화면 캡처
godot --headless --export-release "Web" play/index.html  # 웹 빌드 (내보내기 템플릿 4.3 필요)
```
새 `class_name` 을 추가했으면 한 번 `godot --headless --import` 로 클래스 목록을 갱신한다.
GDScript 는 `var x := dict.get(...)` 처럼 타입을 알 수 없는 값에 `:=` 를 쓰면 오류가 난다. `=` 를 쓴다.

## 디버그
게임 안에서 `` ` `` 또는 `F1` → 디버그 콘솔. `help` 로 명령 목록 (level, give, book, learn, god, hitbox, spawn, chrono …).
