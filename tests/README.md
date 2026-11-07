# 검사 소스

`verify_workspace.ps1`은 환경의 경로·보호 대상·승인 확대·실행자료 경계 반례를 검사한다. `setup/run_tests.ps1 -Suite Workspace`가 호출하며 결과는 D 실행 루트에 둔다. 중앙 runner는 문법·환경 조회·공통 등록도 함께 확인한다.

기본 `setup/run_tests.ps1 -Suite Foundation`은 빌드 후 Core/PassAiFire.Tests.exe의 실제 net48 검사와 verify_foundation.ps1의 경계 검사를 실행한다. 목록 불변성·모든 대기 기능 실행 거부·미지 기능 거부·코어 무의존·의존성 지문·경로 이탈·재분석점·동시 잠금·x64를 확인한다. 실제 소방 기능 시험은 아직 없다. 별도 승인된 CAD 진단은 setup/verify_cad.ps1에서 실행하며 자동·실제 CAD 증거를 분리한다. 기존 제품 runner를 사용하지 않는다.
