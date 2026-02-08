# Core: STTEngine Streaming API Redesign (AsyncThrowingStream + Cancellation)

**Issue**: #5

## Problem
The existing STT streaming API is callback-based and splits lifecycle across two calls:
- `startStreaming(locale:onPartial:)`
- `stopStreaming() -> Transcript`

This shape makes cancellation and resource cleanup easy to get wrong (forgetting to stop, racing stop vs. partial callbacks, unclear ownership when tasks are canceled).

## Goals
- A single, stream-based API that makes lifecycle explicit and consumption structured.
- Clear cancellation semantics:
  - Task cancellation (consumer cancels the task iterating the stream)
  - Explicit cancel (caller can explicitly cancel regardless of task lifetime)
- Keep Core provider-agnostic; Apple Speech integration can follow later.

## Proposed API (Core)
Core protocol becomes:
- `STTEngine.streamTranscripts(locale:) async throws -> STTTranscriptStream`

Where:
- `STTTranscriptStream.transcripts` is `AsyncThrowingStream<Transcript, Error>`
- `STTTranscriptStream.cancel()` is an explicit cancellation handle

### Contract
Implementations MUST release audio/recognition resources when any of the following happens:
- the consumer cancels the Task iterating `transcripts`
- the consumer stops iterating and the stream terminates
- `cancel()` is called

Implementations MUST treat cancellation as safe and idempotent (it may be triggered via multiple paths).

Stream behavior expectations:
- yield partial updates frequently with `isFinal == false`
- yield a final transcript with `isFinal == true` before finishing normally *when possible*
- on cancellation or errors, a final transcript may not be available

## Migration Notes
Old (callback-based):
- begin: `startStreaming(locale:onPartial:)`
- end: `stopStreaming()` to obtain final transcript

New (stream-based):
- call `streamTranscripts(locale:)`
- iterate `for try await transcript in stream.transcripts { ... }`
- stop by:
  - breaking out of the loop (termination), or
  - canceling the consuming task, or
  - calling `await stream.cancel()`

## Open Questions / Follow-ups
- Provide helper utilities in Core for "collect final transcript" patterns (optional).
- Update macOS Apple Speech implementation once it exists.
