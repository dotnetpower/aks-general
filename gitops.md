# gitops



## 📘 GitOps 개요

### ✅ GitOps란?

**GitOps**는 \*Git을 단일 신뢰 원본(Single Source of Truth)\*으로 사용하여 인프라 및 애플리케이션을 배포하고 운영하는 **DevOps 실행 모델**입니다. Kubernetes와 같은 선언적(Declarative) 시스템에서 특히 효과적으로 작동하며, 코드 기반 자동화와 변경 추적성을 극대화합니다.

GitOps는 다음과 같은 핵심 개념을 기반으로 합니다:

---

### 🔑 GitOps의 핵심 원칙

| 원칙                                  | 설명                                      |
| ----------------------------------- | --------------------------------------- |
| **선언적 정의 (Declarative)**            | 인프라와 애플리케이션 상태를 Git 저장소에 YAML 등으로 정의    |
| **버전 관리 (Versioned and Immutable)** | Git에 저장된 상태는 변경 이력과 롤백이 가능하도록 버전 관리됨    |
| **자동화된 동기화 (Automated Sync)**       | 현재 클러스터 상태와 Git 상태를 지속적으로 비교하고 자동으로 동기화 |
| **승인 기반 운영 (Approved Changes)**     | Git PR/MR 기반 변경 승인 및 기록을 통한 운영 신뢰성 확보   |

---

### 🎯 GitOps의 이점

* ✅ **감사 및 추적 가능성 (Auditing)**
  모든 변경 사항은 Git에 기록되어 추적 및 롤백이 용이

* ✅ **자동화된 배포 (CD)**
  CI/CD 중 CD(Continuous Delivery)를 Git 중심으로 자동화

* ✅ **개발자 친화적 운영**
  운영 지식 없이도 Git에서 PR로 배포 가능

* ✅ **표준화 및 보안 강화**
  Git 저장소 접근 제어만으로 변경 통제 가능

---

### 🔧 GitOps와 Argo CD

[**Argo CD**](https://argo-cd.readthedocs.io/)는 CNCF(Cloud Native Computing Foundation) 프로젝트로, GitOps 방식의 Kubernetes 애플리케이션 배포를 실현하는 도구입니다.

| 기능               | 설명                                     |
| ---------------- | -------------------------------------- |
| **Git 저장소 모니터링** | 지정한 Git 저장소의 변경을 감지                    |
| **자동/수동 동기화**    | 클러스터와 Git 상태 간 자동 동기화 가능               |
| **롤백 및 비교**      | 클러스터와 Git 저장소 상태의 diff 확인 및 롤백         |
| **RBAC 및 UI 제공** | Web UI, CLI, API를 통해 손쉬운 관리 및 권한 제어 제공 |

---


## 🚀 AKS에 Argo CD 설치 및 GitOps 환경 구성 가이드

### 1️⃣ Argo CD 설치

1. **Argo CD 전용 네임스페이스 생성**

   ```bash
   kubectl create namespace argocd
   ```

2. **Argo CD 설치 매니페스트 적용**

   ```bash
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```

   이 명령어는 Argo CD의 모든 구성 요소(서버, 컨트롤러, 리포지터리 서버 등)를 설치합니다. 설치가 완료되면 다음 명령어로 상태를 확인할 수 있습니다:

   ```bash
   kubectl get pods -n argocd
   ```



---

### 2️⃣ Argo CD API 서버 접근 설정

기본적으로 Argo CD의 API 서버는 외부에 노출되어 있지 않으므로, 외부에서 접근하기 위해서는 다음 중 하나의 방법을 선택해야 합니다:

* **LoadBalancer 서비스 타입으로 변경**

  ```bash
  kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
  ```

  이 설정을 적용하면 외부 IP를 통해 Argo CD UI에 접근할 수 있습니다. 외부 IP는 다음 명령어로 확인할 수 있습니다:
  External-IP 로 접속

  ```bash
  kubectl get svc argocd-server -n argocd
  ```

* **포트 포워딩 사용**

  ```bash
  kubectl port-forward svc/argocd-server -n argocd 8080:443
  ```

  이 방법을 사용하면 로컬 머신의 `https://localhost:8080`을 통해 Argo CD UI에 접근할 수 있습니다.



---

### 3️⃣ Argo CD CLI 설치 및 로그인

1. **Argo CD CLI 설치**

   운영 체제에 따라 다음 명령어로 Argo CD CLI를 설치할 수 있습니다:

   * **macOS (Homebrew 사용)**

     ```bash
     brew install argocd
     ```

   * **Windows (Chocolatey 사용)**

     ```bash
     choco install argocd
     ```

   * **Linux**

     최신 버전의 CLI를 다운로드하여 설치합니다:

     ```bash
     VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
     curl -sSL -o argocd-linux-amd64 "https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64"
     sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
     rm argocd-linux-amd64
     ```

2. **초기 관리자 비밀번호 확인**

   Argo CD 설치 시 생성된 초기 관리자 비밀번호는 다음 명령어로 확인할 수 있습니다:
   ID: admin

   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

3. **Argo CD CLI를 통한 로그인**

   외부 IP 또는 포트 포워딩 주소를 사용하여 Argo CD에 로그인합니다:

   ```bash
   argocd login <ARGOCD_SERVER>
   ```

   예를 들어, 포트 포워딩을 사용한 경우:

   ```bash
   argocd login localhost:8080
   ```

   로그인 후 비밀번호를 변경하는 것이 좋습니다:

   ```bash
   argocd account update-password
   ```



---

### 4️⃣ 애플리케이션 등록 및 GitOps 구성

1. **애플리케이션 매니페스트 저장소 준비**

   Git 리포지터리에 Kubernetes 매니페스트(YAML 파일)를 저장합니다. 예를 들어, `nginx` 배포를 위한 매니페스트를 `apps/nginx/` 디렉터리에 저장할 수 있습니다.

2. **Argo CD에 애플리케이션 등록**

   CLI를 사용하여 애플리케이션을 등록합니다:

   ```bash
   argocd app create nginx-app \
     --repo https://github.com/your-org/your-repo.git \
     --path apps/nginx \
     --dest-server https://kubernetes.default.svc \
     --dest-namespace default \
     --sync-policy automated
   ```

   위 명령어에서:

   * `--repo`: Git 리포지터리 URL
   * `--path`: 매니페스트가 위치한 경로
   * `--dest-server`: 대상 Kubernetes API 서버 (동일 클러스터인 경우 `https://kubernetes.default.svc`)
   * `--dest-namespace`: 배포할 네임스페이스
   * `--sync-policy automated`: 변경 사항을 자동으로 동기화

3. **애플리케이션 동기화**

   애플리케이션을 수동으로 동기화하려면 다음 명령어를 사용합니다:

   ```bash
   argocd app sync nginx-app
   ```



---

### 5️⃣ 추가 구성: RBAC 및 보안 설정

* **RBAC 설정**: Argo CD의 역할 기반 접근 제어(RBAC)를 설정하여 사용자별 권한을 관리할 수 있습니다. `argocd-rbac-cm` ConfigMap을 수정하여 역할과 권한을 정의합니다.

* **TLS 인증서 설정**: 자체 인증서 또는 Let's Encrypt를 사용하여 Argo CD 서버의 TLS 인증서를 설정할 수 있습니다. Ingress Controller와 Cert-Manager를 함께 사용하여 자동화된 인증서 관리를 구현할 수 있습니다.

* **Ingress 설정**: NGINX Ingress Controller를 사용하여 Argo CD에 대한 접근을 도메인 기반으로 설정할 수 있습니다. 이를 통해 사용자 친화적인 URL로 Argo CD UI에 접근할 수 있습니다.



## AKS 클러스터 생성
[Workload Identity를 사용하여 ADLS Gen2(Storage Account) 에 접근하는 방법 ](./workload-id.md)

## ACR 생성 및 클러스터에 연결

### ACR 생성
```bash
ACR_NAME="acradls01"

az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Standard \
  --location $LOCATION

```

### 클러스터에 연결
```bash
az aks update \
  --name $AKS_NAME \
  --resource-group $RESOURCE_GROUP \
  --attach-acr $ACR_NAME

```