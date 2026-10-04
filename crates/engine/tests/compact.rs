use async_trait::async_trait;
use futures::{StreamExt, stream::BoxStream};
use std::sync::{Arc, Mutex};
use zeron_engine::{EngineCore, HarnessRegistry};
use zeron_harness::{Harness, HarnessError, RunControls};
use zeron_proto::{
    AgentEvent, ChatConfig, DoneStatus, HarnessId, Model, ReasoningLevel, RunRequest, SandboxLevel,
    SteeringMode,
};
use zeron_rpc::methods;

/// A [`HarnessId::Droid`] stand-in that records the requests it runs.
struct CaptureDroid(Arc<Mutex<Vec<RunRequest>>>);
#[async_trait]
impl Harness for CaptureDroid {
    fn id(&self) -> HarnessId {
        HarnessId::Droid
    }
    fn display_name(&self) -> &str {
        "CaptureDroid"
    }
    fn supports_steering(&self) -> bool {
        false
    }
    fn steering_mode(&self) -> SteeringMode {
        SteeringMode::TurnBoundary
    }
    fn reasoning_levels(&self) -> &[ReasoningLevel] {
        &[]
    }
    async fn models(&self) -> Result<Vec<Model>, HarnessError> {
        Ok(vec![])
    }
    async fn run(
        &self,
        request: RunRequest,
        _: RunControls,
    ) -> Result<BoxStream<'static, Result<AgentEvent, HarnessError>>, HarnessError> {
        self.0.lock().unwrap().push(request);
        Ok(futures::stream::iter(vec![Ok(AgentEvent::Done {
            status: DoneStatus::Completed,
            result: None,
            error: None,
            session_id: Some("droid-session".into()),
        })])
        .boxed())
    }
}

/// A [`HarnessId::Droid`] harness whose turn never settles on its own
/// (compact must refuse it, like rewind does).
struct PendingDroid;
#[async_trait]
impl Harness for PendingDroid {
    fn id(&self) -> HarnessId {
        HarnessId::Droid
    }
    fn display_name(&self) -> &str {
        "PendingDroid"
    }
    fn supports_steering(&self) -> bool {
        false
    }
    fn steering_mode(&self) -> SteeringMode {
        SteeringMode::TurnBoundary
    }
    fn reasoning_levels(&self) -> &[ReasoningLevel] {
        &[]
    }
    async fn models(&self) -> Result<Vec<Model>, HarnessError> {
        Ok(vec![])
    }
    async fn run(
        &self,
        _: RunRequest,
        _: RunControls,
    ) -> Result<BoxStream<'static, Result<AgentEvent, HarnessError>>, HarnessError> {
        Ok(futures::stream::pending().boxed())
    }
}

fn droid_config() -> ChatConfig {
    ChatConfig {
        harness: HarnessId::Droid,
        model: Some("auto".into()),
        reasoning: None,
        model_options: Default::default(),
        sandbox: SandboxLevel::WorkspaceWrite,
    }
}

fn request(prompt: &str) -> RunRequest {
    RunRequest {
        mcp: None,
        prompt: prompt.into(),
        harness: Some(HarnessId::Mock),
        model: None,
        reasoning: None,
        model_options: Default::default(),
        cwd: "/tmp".into(),
        sandbox: SandboxLevel::WorkspaceWrite,
        auto_approve: true,
        resume: None,
        attachments: vec![],
        worktree: None,
    }
}

#[tokio::test]
async fn compact_refuses_chats_without_a_compactable_harness() {
    let dir = tempfile::tempdir().unwrap();
    let registry = HarnessRegistry::new();
    let core = EngineCore::assemble(dir.path(), Arc::new(registry), HarnessId::Mock, None).unwrap();
    core.workspace
        .create_chat(
            "main",
            None,
            Some(&core.device_id),
            None,
            Some("/tmp".into()),
        )
        .unwrap();
    let client = zeron_rpc::memory_client(core.rpc_service());

    // No harness configured: nothing to compact.
    let err = client
        .call(
            methods::COMPACT_CHAT,
            serde_json::json!({ "chatId": "main" }),
        )
        .await
        .unwrap_err();
    assert!(err.to_string().contains("no agent harness"), "{err:?}");

    // A non-compactable harness is rejected, not executed.
    let mut config = droid_config();
    config.harness = HarnessId::Mock;
    core.workspace
        .create_chat(
            "other",
            None,
            Some(&core.device_id),
            Some(config),
            Some("/tmp".into()),
        )
        .unwrap();
    let err = client
        .call(
            methods::COMPACT_CHAT,
            serde_json::json!({ "chatId": "other" }),
        )
        .await
        .unwrap_err();
    assert!(
        err.to_string()
            .contains("only supported for OpenCode and Droid"),
        "{err:?}"
    );
    core.shutdown().await;
    drop(client);
}

#[tokio::test]
async fn compact_refuses_a_live_turn() {
    let dir = tempfile::tempdir().unwrap();
    let registry = HarnessRegistry::new();
    registry.register(Arc::new(PendingDroid));
    let core =
        EngineCore::assemble(dir.path(), Arc::new(registry), HarnessId::Droid, None).unwrap();
    core.workspace
        .create_chat(
            "main",
            None,
            Some(&core.device_id),
            Some(droid_config()),
            Some("/tmp".into()),
        )
        .unwrap();
    core.sessions
        .dispatch("main", HarnessId::Droid, request("hello"), None)
        .await
        .unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        while !core.sessions.turn_in_flight("main") {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let client = zeron_rpc::memory_client(core.rpc_service());
    let err = client
        .call(
            methods::COMPACT_CHAT,
            serde_json::json!({ "chatId": "main" }),
        )
        .await
        .unwrap_err();
    assert!(err.to_string().contains("Stop the agent"), "{err:?}");
    core.sessions.interrupt("main").await.unwrap();
    core.shutdown().await;
    drop(client);
}

#[tokio::test]
async fn compact_droid_queues_a_compress_turn_with_the_requested_model() {
    let dir = tempfile::tempdir().unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let registry = HarnessRegistry::new();
    registry.register(Arc::new(CaptureDroid(requests.clone())));
    let core =
        EngineCore::assemble(dir.path(), Arc::new(registry), HarnessId::Droid, None).unwrap();
    core.workspace
        .create_chat(
            "main",
            None,
            Some(&core.device_id),
            Some(droid_config()),
            Some("/tmp".into()),
        )
        .unwrap();
    let client = zeron_rpc::memory_client(core.rpc_service());

    client
        .call(
            methods::COMPACT_CHAT,
            serde_json::json!({ "chatId": "main", "model": "gpt-5.6-sol" }),
        )
        .await
        .unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        while requests.lock().unwrap().is_empty() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let sent = requests.lock().unwrap()[0].clone();
    assert_eq!(sent.prompt, "/compress");
    assert_eq!(sent.harness, Some(HarnessId::Droid));
    assert_eq!(sent.model.as_deref(), Some("gpt-5.6-sol"));
    assert_eq!(sent.cwd, "/tmp");
    core.shutdown().await;
    drop(client);
}

#[tokio::test]
async fn compact_opencode_needs_a_provider_session_first() {
    let dir = tempfile::tempdir().unwrap();
    let registry = HarnessRegistry::new();
    let core =
        EngineCore::assemble(dir.path(), Arc::new(registry), HarnessId::Opencode, None).unwrap();
    let mut config = droid_config();
    config.harness = HarnessId::Opencode;
    core.workspace
        .create_chat(
            "main",
            None,
            Some(&core.device_id),
            Some(config),
            Some("/tmp".into()),
        )
        .unwrap();
    let client = zeron_rpc::memory_client(core.rpc_service());
    let err = client
        .call(
            methods::COMPACT_CHAT,
            serde_json::json!({ "chatId": "main" }),
        )
        .await
        .unwrap_err();
    assert!(err.to_string().contains("No OpenCode session"), "{err:?}");
    core.shutdown().await;
    drop(client);
}
