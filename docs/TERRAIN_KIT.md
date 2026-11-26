# 섬 지형 조각 만들기 (바위 키트)

섬은 이렇게 만들어집니다.

1. **모양(코드)**: 노이즈로 섬 모양과 높이(1~3단)를 랜덤으로 정합니다. `scripts/island/island_generator.gd`
2. **윗면(코드)**: 걸어 다니는 풀밭은 코드가 한 장으로 깝니다. 그래서 조각 사이 이음새가 발밑에 생기지 않습니다.
3. **절벽(조각)**: 높이가 바뀌는 외곽선을 따라 모양에 맞는 바위 조각을 하나씩 세웁니다. `scripts/island/cliff_mesh.gd`
   - 곧은 면 → `cliff`, 두 단 이상 이어진 큰 절벽 → `cliff_tall`
   - 튀어나온 모서리 → `cliff_corner_out`, 파인 모서리 → `cliff_corner_in`
   - 바닷가 낮은 땅 가장자리 → `shore_rock`
4. **변형(코드)**: 조각마다 가로 폭, 앞뒤 두께, 각도, 밝기를 조금씩 다르게 합니다. 같은 이름 파일이 여러 개면 섞어 씁니다.
5. **셰이더**: 모든 바위 조각에 같은 셰이더를 입힙니다. 옆면은 가로 지층 줄, 위를 보는 면은 이끼(풀색), 물가는 젖은 색입니다.
   `assets/shaders/terrain_rock.gdshader`

지금은 파일이 없어서 코드가 만든 **임시 바위**가 들어가 있습니다. 아래 파일을 `assets/models/rock_kit/` 폴더에 넣으면 코드 수정 없이 바로 바뀝니다.
없는 종류는 임시 바위나 비슷한 조각(`cliff`)으로 대신하므로 **한두 개씩 차례로 넣어도 됩니다.**

## 만들 조각 목록 (13개)

크기 단위는 m (섬 한 칸 = 1m, 병사 키 = 0.45m). 파일 크기는 게임이 자동으로 맞추므로 **비율만** 맞으면 됩니다.

| 순서 | 파일 이름 | 무엇 | 가로 × 높이 × 두께 (비율) |
|---|---|---|---|
| 1 | `rock_kit/cliff_01.glb` | 곧은 절벽 한 단 | 1.0 × 1.0 × 0.45 |
| 2 | `rock_kit/cliff_02.glb` | 곧은 절벽 한 단 (모양 다르게) | 1.0 × 1.0 × 0.45 |
| 3 | `rock_kit/cliff_03.glb` | 곧은 절벽 한 단 (모양 다르게) | 1.0 × 1.0 × 0.45 |
| 4 | `rock_kit/cliff_tall_01.glb` | 곧은 절벽 두 단 | 1.0 × 2.0 × 0.45 |
| 5 | `rock_kit/cliff_tall_02.glb` | 곧은 절벽 두 단 (모양 다르게) | 1.0 × 2.0 × 0.45 |
| 6 | `rock_kit/cliff_corner_out_01.glb` | 튀어나온 모서리 (앞면이 살짝 볼록) | 0.7 × 1.0 × 0.45 |
| 7 | `rock_kit/cliff_corner_in_01.glb` | 파인 모서리 (앞면이 살짝 오목) | 0.7 × 1.0 × 0.45 |
| 8 | `rock_kit/shore_rock_01.glb` | 바닷가 낮은 바위턱 (비탈) | 1.0 × 0.65 × 0.45 |
| 9 | `rock_kit/shore_rock_02.glb` | 바닷가 낮은 바위턱 (모양 다르게) | 1.0 × 0.65 × 0.45 |
| 10 | `rock.glb` | 길을 막는 큰 바위 하나 | 0.8 × 0.55 × 0.8 |
| 11 | `stairs.glb` | 바위를 깎은 돌계단 (높은 쪽이 뒤) | 0.62 × 0.5 × 0.5 |
| 12 | `tree.glb` | 나무 | 0.35 × 0.7 × 0.35 |
| 13 | `bush.glb` | 덤불 | 0.32 × 0.2 × 0.32 |

**먼저 만들 것**: 1번(`cliff_01`) 하나만 넣어도 섬 전체 절벽이 그 모델로 바뀝니다. 마음에 들면 2~9번을 채우세요.
10~13번은 `assets/models/` 바로 아래에 넣습니다(이미 `stairs.glb`가 있으면 덮어쓰기).

## 조각 공통 약속 (중요)

- **정면에 바위 얼굴**: Blender 정면 보기(숫자패드 `1`)에서 바위 면이 보이게 둡니다. 게임이 알아서 바깥을 보게 돌립니다.
- **윗면은 평평하게**: 맨 위는 풀밭 높이와 같아집니다. 위로 튀어나온 뾰족한 바위가 있으면 풀밭 위로 삐져나옵니다.
- **뒷면은 신경 쓰지 않아도 됨**: 땅 속에 묻혀 안 보입니다. 평평하게 잘라도 됩니다.
- **양옆 끝은 조금 얇게**: 옆 조각과 10% 정도 겹쳐서 세웁니다. 양 끝이 두꺼우면 겹친 자리가 혹처럼 보입니다.
- **원점 위치는 상관없음**: 게임이 모델을 감싸는 상자를 재서 바닥 가운데로 옮깁니다.
- **색·텍스처는 없어도 됨**: 게임이 공용 바위 셰이더로 다시 칠합니다(조각끼리 색이 안 맞는 문제 방지).
  원래 색을 쓰고 싶으면 `scripts/core/asset_library.gd` 의 `ROCK_SHADER_ON_FILES` 를 `false` 로 바꾸세요.
- **삼각형 수**: 조각 하나에 2,000~5,000개면 충분합니다. 섬 하나에 조각이 150~250개 들어갑니다.

## 1단계: ChatGPT로 컨셉 그림

먼저 스타일을 고정하는 문장을 한 번 붙여 넣고, 조각마다 아래 요청을 이어서 보내세요.

> 지금부터 게임용 바위 절벽 조각 그림을 여러 장 그릴 거야. 모든 그림에 같은 스타일을 써 줘.
> 스타일: 로우폴리 3D, 큼직하게 깎인 각진 면, 가로로 켜켜이 쌓인 지층 줄과 침식된 홈, 차분한 회백색 바위, 윗면 가장자리에만 얇은 이끼.
> 흰 배경, 그림자 없음, 정면에서 똑바로 본 모습 한 장 + 45도 비스듬한 모습 한 장. 물체 하나만, 잘리지 않게 전체가 보이게.

조각별 요청:

| 파일 | ChatGPT 요청 |
|---|---|
| `cliff_01~03` | 정사각형에 가까운 절벽 벽 조각을 그려 줘. 가로와 높이가 같고 두께는 가로의 절반. 윗면은 평평하고 앞면에는 지층 턱이 3~4줄. (3장은 지층 모양·갈라진 틈 위치를 다르게) |
| `cliff_tall_01~02` | 세로로 긴 절벽 벽 조각. 높이가 가로의 2배, 두께는 가로의 절반. 지층 턱 6~7줄, 중간에 크게 갈라진 세로 틈 하나. |
| `cliff_corner_out_01` | 폭이 좁은 절벽 조각(가로:높이 = 0.7:1). 앞면이 바깥으로 살짝 볼록하게 둥근 모서리 바위. |
| `cliff_corner_in_01` | 폭이 좁은 절벽 조각(가로:높이 = 0.7:1). 앞면이 안쪽으로 살짝 오목하게 파인 바위. |
| `shore_rock_01~02` | 바닷가의 낮고 넓은 바위턱. 가로:높이 = 3:2, 앞쪽으로 완만하게 비탈진 둥근 바위 덩어리들, 아래쪽은 물에 젖어 조금 어둡게. |
| `rock` | 길을 막는 둥글고 각진 큰 바위 하나. 가로·세로가 같고 높이는 그 70%. |
| `stairs` | 절벽 옆에 붙은, 바위를 깎아 만든 돌계단 4~5칸. 정면에서 봤을 때 계단이 보는 사람 쪽(앞)으로 높아지게. |
| `tree` | 키 큰 침엽수 한 그루, 단순한 원뿔 2~3층 잎, 짧은 줄기. |
| `bush` | 낮고 둥근 덤불 하나, 잎 덩어리 3~4개. |

## 2단계: Meshy 또는 Tripo로 3D 변환

**그림 → 3D (추천)**: 1단계 그림 중 "정면" 그림을 Image to 3D에 올립니다.

- Meshy: Image to 3D → Art Style `Low Poly`(없으면 기본) → Topology `Triangle` → Target Polycount `3,000` 정도 → Texture는 꺼도 됨 → `.glb`로 내려받기
- Tripo: Image to 3D → Style 기본 → Generate → (선택) Smart Low Poly → Export `glb`

**글 → 3D**: 그림 없이 바로 만들 때 쓰는 영어 문장입니다(이 도구들은 영어를 더 잘 알아듣습니다).

| 파일 | Meshy / Tripo 프롬프트 |
|---|---|
| `cliff_01~03` | `low poly stylized cliff wall segment, square slab, flat top, flat back, chunky angular rock facets, horizontal sedimentary layers with eroded ledges, pale grey limestone, game asset, single object` |
| `cliff_tall_01~02` | `low poly stylized tall cliff wall segment, height twice the width, flat top, flat back, chunky angular facets, horizontal rock strata, one deep vertical crack, pale grey limestone, game asset` |
| `cliff_corner_out_01` | `low poly narrow cliff corner piece, front face gently convex and rounded, flat top, flat back, angular facets, horizontal rock layers, pale grey stone, game asset` |
| `cliff_corner_in_01` | `low poly narrow cliff piece, front face gently concave, flat top, flat back, angular facets, horizontal rock layers, pale grey stone, game asset` |
| `shore_rock_01~02` | `low poly wide low coastal rock ledge, gently sloping front, flat top, rounded angular boulders, pale grey stone, game asset` |
| `rock` | `low poly single boulder, chunky angular facets, pale grey stone, game asset` |
| `stairs` | `low poly stone stairs carved from rock, 5 steps rising toward the viewer, pale grey stone, game asset` |
| `tree` | `low poly stylized pine tree, three stacked cone layers, short trunk, muted green, game asset` |
| `bush` | `low poly round shrub, 3 to 4 leaf clumps, muted green, game asset` |

## 3단계: (필요하면) Blender로 정리

대부분 그대로 넣어도 됩니다. 아래 경우만 손보세요.

- **바위 얼굴이 정면이 아님**: 숫자패드 `1`로 정면을 보고, 얼굴이 보이도록 `R` `Z` `90`(또는 180)으로 돌린 뒤 `Ctrl+A` → All Transforms.
- **윗면이 울퉁불퉁**: 편집 모드에서 맨 위 점들을 선택 → `S` `Z` `0` 으로 평평하게.
- 내보내기: File → Export → glTF 2.0 → 형식 `glTF Binary (.glb)` → `+Y Up` 체크(기본값).

## 4단계: 넣고 확인

1. 파일을 `D:\Game\RE-Bad-North-Game-\assets\models\rock_kit\` 에 넣습니다(폴더가 없으면 만들기).
2. Godot을 열면 자동으로 불러옵니다. 출력 창에 `바위 조각: [cliff, ...]` 이 보이면 인식된 것입니다.
3. 이름을 알아보지 못하면 `바위 조각 이름을 알아보지 못했습니다` 경고가 나옵니다. 위 표의 이름 + `_01` 같은 번호로 바꾸세요.
4. 바위 얼굴이 섬 안쪽을 보고 있으면(절벽이 뒷면처럼 평평하게 보이면) 3단계의 방향 맞추기를 하세요.

## 참고

- 이 방식은 장르에서 흔히 쓰는 "모양은 코드, 겉모습은 조각" 구조입니다. 다른 게임의 모델·그림을 가져오지 않고 우리 조각만 씁니다.
- 걷는 규칙(같은 높이 또는 계단으로만 이동)은 그림과 상관없이 `island_generator.gd` 의 `tiles` / `stairs` 가 정합니다.
- 지형 모양을 바꾸고 싶으면 `island_generator.gd` 의 `_make_layout()` 숫자를 조절합니다. 예: 고원 비율 `0.5`, 봉우리 비율 `0.38`.
