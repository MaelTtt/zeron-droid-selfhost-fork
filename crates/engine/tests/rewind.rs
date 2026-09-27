use async_trait::async_trait;
use futures::{StreamExt, stream::BoxStream};
use std::sync::{Arc, Mutex};
use zeron_doc::{MessagePart, MessageRole, MessageStatus, SessionMessageEntry};
use zeron_engine::{EngineCore, HarnessRegistry};
use zeron_harness::{Harness, HarnessError, RunControls};
use zeron_proto::{
    AgentEvent, DoneStatus, HarnessId, Model, ReasoningLevel, RunRequest, SandboxLevel,
    SteeringMode,
};
use zeron_rpc::methods;

struct Capture(Arc<Mutex<Vec<RunRequest>>>);
#[async_trait]
impl Harness for Capture {
    fn id(&self) -> HarnessId {
        HarnessId::Mock
    }
    fn display_name(&self) -> &str {
        "Capture"
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
        Ok(futures::stream::iter(vec![
            Ok(AgentEvent::TextDelta {
                text: "answer".into(),
            }),
            Ok(AgentEvent::Done {
                status: DoneStatus::Completed,
                result: None,
                error: None,
                session_id: Some("fresh-provider-session".into()),
            }),
        ])
        .boxed())
    }
}

fn message(id: &str, role: MessageRole, text: &str) -> SessionMessageEntry {
    SessionMessageEntry {
        duration_ms: None,
        id: id.into(),
        role,
        parts: vec![MessagePart::Text {
            id: format!("{id}-text"),
            text: text.into(),
        }],
        created_at: 1,
        device_id: "device".into(),
        status: Some(MessageStatus::Complete),
        continuation_of: None,
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
async fn rewind_truncates_and_the_next_run_forgets_the_rewound_turns() {
    let dir = tempfile::tempdir().unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let registry = HarnessRegistry::new();
    registry.register(Arc::new(Capture(requests.clone())));
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
    core.workspace
        .set_chat_harness_session("main", "old-provider-session", "/tmp");
    let chat = core.doc_host.open("main").unwrap();
    for entry in [
        message("u1", MessageRole::User, "Remember PINEAPPLE"),
        message("a1", MessageRole::Assistant, "I remember PINEAPPLE"),
        message("u2", MessageRole::User, "Now remember MANGO"),
        message("a2", MessageRole::Assistant, "I remember MANGO"),
    ] {
        chat.doc().push_message(&entry).unwrap();
    }
    let client = zeron_rpc::memory_client(core.rpc_service());

    let rejected = client
        .call(
            methods::REWIND_CHAT,
            serde_json::json!({ "chatId": "main", "messageId": "a1" }),
        )
        .await;
    assert!(rejected.is_err(), "only user messages are rewind points");

    client
        .call(
            methods::REWIND_CHAT,
            serde_json::json!({ "chatId": "main", "messageId": "u2" }),
        )
        .await
        .unwrap();
    let ids: Vec<_> = chat
        .doc()
        .read_entries()
        .unwrap()
        .into_iter()
        .map(|e| e.id)
        .collect();
    assert_eq!(ids, ["u1", "a1"]);

    core.sessions
        .dispatch(
            "main",
            HarnessId::Mock,
            request("What do you remember?"),
            None,
        )
        .await
        .unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        while requests.lock().unwrap().is_empty() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let sent = requests.lock().unwrap()[0].clone();
    assert_eq!(sent.resume, None, "the old provider session is dropped");
    assert!(sent.prompt.contains("PINEAPPLE"));
    assert!(!sent.prompt.contains("MANGO"));
    assert!(sent.prompt.ends_with("What do you remember?"));
    core.shutdown().await;
    drop(client);
}
