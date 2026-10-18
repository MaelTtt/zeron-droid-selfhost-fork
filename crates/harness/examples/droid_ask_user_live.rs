//! Live check (not part of CI): the real `droid exec --output-format acp`
//! asking through ACP form elicitation, answered the way the engine's question
//! panel answers. Run from the repo root:
//!
//! ```sh
//! cargo run -p zeron-harness --example droid_ask_user_live
//! ```
//!
//! Needs a signed-in Droid CLI (`droid` in ~/.local/bin or PATH); costs one
//! small turn on the session's model.
//!
//! The callback below is the point of this check. `Wizard::answers`
//! (`crates/ui/src/composer.rs`) answers a question the harness marked
//! `multiline` with the free-text box *alone* — so a clicked option comes back
//! as an empty label there. Imitating that rule here reproduces what the real
//! panel does to a question shape, without needing the engine running.

use futures::StreamExt;
use tokio::sync::{mpsc, oneshot};
use zeron_harness::{AcpHarness, CancellationToken, Harness, RunControls};
use zeron_proto::{AgentEvent, RunRequest, SandboxLevel, UserInputAnswer, UserInputQuestion};

/// What the engine's question panel sends for a click on option `ix` when the
/// free-text box is left empty (`Wizard::answers`).
fn wizard_click(question: &UserInputQuestion, ix: usize) -> UserInputAnswer {
    let labels = if question.multiline {
        vec![String::new()]
    } else {
        question.options.get(ix).cloned().into_iter().collect()
    };
    UserInputAnswer {
        question_id: question.id.clone(),
        labels,
    }
}

#[tokio::main]
async fn main() {
    let (steer_tx, steer_rx) = mpsc::channel(8);
    let token = CancellationToken::new();
    let controls = RunControls {
        realtime: None,
        execution_lease: None,
        request_input: Box::new(|questions| {
            let (tx, rx) = oneshot::channel();
            let answers: Vec<UserInputAnswer> = questions
                .iter()
                .map(|question| {
                    eprintln!(
                        "[panel] header={:?} question={:?} options={:?} multi={} multiline={}",
                        question.header,
                        question.question,
                        question.options,
                        question.multi_select,
                        question.multiline
                    );
                    // Click the option the panel would show as row 1.
                    let ix = usize::from(question.options.len() > 1);
                    let answer = wizard_click(question, ix);
                    eprintln!("[panel] click row {ix} -> labels={:?}", answer.labels);
                    answer
                })
                .collect();
            let _ = tx.send(answers);
            rx
        }),
        steering: steer_rx,
        interrupt: token.clone(),
        turn: Default::default(),
    };
    let request = RunRequest {
        mcp: None,
        prompt: "Call the AskUser tool right now with one question: which color, red or blue? \
                 Do not use any other tool."
            .into(),
        harness: None,
        model: None,
        reasoning: None,
        model_options: serde_json::Map::new(),
        cwd: "/tmp/acp-probe/ws".into(),
        sandbox: SandboxLevel::WorkspaceWrite,
        auto_approve: true,
        attachments: Vec::new(),
        worktree: None,
        resume: None,
    };
    std::fs::create_dir_all("/tmp/acp-probe/ws").unwrap();

    let harness = AcpHarness::droid();
    eprintln!("[live] harness={:?}", harness.id());
    let mut stream = harness.run(request, controls).await.expect("run starts");
    while let Some(event) = stream.next().await {
        match event {
            Ok(AgentEvent::TextDelta { text }) => eprintln!("[text] {text:?}"),
            Ok(AgentEvent::ToolCall { id, call }) => eprintln!("[tool] {id} {call:?}"),
            Ok(AgentEvent::ToolResult {
                id,
                is_error,
                output,
                ..
            }) => eprintln!("[result] {id} error={is_error} output={output:?}"),
            Ok(AgentEvent::Done { status, error, .. }) => {
                eprintln!("[done] {status:?} {error:?}");
            }
            Ok(other) => eprintln!("[event] {other:?}"),
            Err(error) => eprintln!("[error] {error}"),
        }
    }
    drop(steer_tx);
}
