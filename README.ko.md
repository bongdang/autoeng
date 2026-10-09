# Autoeng

[English](README.md) | 한국어

터미널 명령을 영어 입력 상태로 시작하세요.

Autoeng는 터미널로 이동하거나 터미널 창·iTerm2 탭을 전환할 때 지정한 영어 입력 소스로 바꿔 주는 macOS 메뉴 막대 앱입니다. 같은 창·탭에서 직접 다른 입력 소스를 선택하면 그 상태를 유지합니다.

## 주요 기능

- iTerm2와 macOS Terminal을 지원합니다.
- 앱 진입과 창 이동 시 영어로 전환하며, 같은 대상 앱의 별도 프로세스 사이 이동도 처리합니다.
- iTerm2 탭 전환을 지원합니다.
- **Auto / Eng** 메뉴에서 일시 중지·재개·수동 전환을 제공합니다.
- 영어 입력 소스와 대상 앱 설정을 저장합니다.

## 설치

현재는 소스에서 직접 빌드해 설치합니다. Homebrew 패키지는 제공하지 않습니다.

최소한 macOS와 Swift 6 이상을 제공하는 Apple Command Line Tools가 필요하며, 빌드 스크립트는 Python 3을 사용합니다. Xcode 전체 앱 설치는 필요하지 않습니다.

### 1. Command Line Tools 설치

아직 설치하지 않았다면 다음 명령을 실행합니다.

```sh
xcode-select --install
```

설치 후 선택된 도구 경로와 Swift 버전을 확인합니다.

```sh
xcode-select -p
xcrun swift --version
```

### 2. 빌드와 실행

저장소의 루트 디렉터리에서 실행합니다.

```sh
# 최초 한 번: 로컬 서명 준비
./scripts/setup-local-signing.sh
./scripts/trust-local-signing.sh

./scripts/build-app.sh
open build/Autoeng.app
```

로컬 서명은 재빌드할 때 손쉬운 사용 권한을 유지하는 데 도움이 됩니다. 설정 스크립트는 사용자의 Mac에서 서명 인증서를 만들고 사용자 영역에 코드 서명 도구용 신뢰만 설정합니다. 이 소스 빌드에는 Apple Developer 계정이 필요하지 않습니다.

생성된 인증서·비밀 키·암호는 Git에서 제외된 `.local-signing/`에 보관합니다. 앱 식별을 유지하도록 이 폴더를 보존하세요. 다시 빌드하기 전에는 메뉴에서 Autoeng를 종료합니다.

### 3. 창·탭 감지 허용

**시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**에서 **`build/Autoeng.app`**을 추가하고 허용합니다. 목록에 없다면 `+`로 추가하세요. 경로 이동(`⇧⌘G`)으로 프로젝트의 `build` 폴더를 선택할 수 있습니다.

권한을 허용한 뒤 앱을 다시 실행합니다.

```sh
open build/Autoeng.app
```

창·탭 감지에는 손쉬운 사용 권한이 필요합니다. 권한이 없어도 대상 앱 진입 시 전환은 동작합니다. 서명 인증서를 변경한 뒤 권한이 동작하지 않으면 이전 항목을 제거하고 현재 앱을 다시 추가합니다.

## 사용법

메뉴 막대의 **Auto / Eng**를 엽니다.

1. **English input source**에서 ABC 또는 U.S. 등 설치된 영어 소스를 선택합니다.
2. **Target apps**에서 iTerm2 또는 Terminal을 선택합니다.
3. 대상 앱·다른 창·다른 iTerm2 탭으로 이동하면 영어로 시작할 수 있습니다.

앱·창·탭 이동에도 현재 입력 상태를 유지하려면 **Pause automatic switching**을 선택합니다. **Resume automatic switching**으로 재개하면 현재 대상에 영어 규칙을 적용합니다. **Switch to English**는 일시 중지 중에도 사용할 수 있습니다.

## 제한 사항

- iTerm2 탭 감지는 접근 가능한 탭 막대가 표시되어 있어야 합니다.
- 탭 전환은 iTerm2에서 지원하며, macOS 기본 Terminal 앱에서는 지원하지 않습니다.
- 같은 탭 안의 분할 패널 사이 이동은 별도 전환 대상으로 처리하지 않습니다.
- 대상 앱에서 나갈 때 이전 입력 소스를 복원하지 않습니다.
- 구버전 macOS, Intel Mac, 한글·영어 이외의 입력기는 아직 검증하지 않았습니다.

## 개인정보

앱 활성화와 손쉬운 사용의 선택 상태를 사용합니다. 키 입력을 가로채거나 터미널 내용·클립보드를 읽지 않으며, 네트워크 통신을 하지 않습니다.

## 라이선스

[MIT](LICENSE).
