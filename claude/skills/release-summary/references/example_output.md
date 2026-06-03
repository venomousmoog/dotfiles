Conveyors: `surreal/aria_ai_interactions` (R620 → R657) and `surreal/aria_ai_event_generators` (R677 → R735)

### Agent Features (user interactions)

* [+] Calendar answers now include building location, room capacity, meeting notes, and organizer name
* [+] Users can send themselves Google Chat reminders and notifications directly from the agent
* [+] Custom skills can be created to extend what the agent can do, with the ability to list and manage available skills (gatekeeper)
* [+] Several additional MCP tools available under gatekeeper (google doc, MCP timeline tools)
* [=] Improved calendar tool accuracy - the agent better understands calendar-related questions and selects the right tool
* [=] Shared conversation threads now focus exclusively on shared speech events, preventing unrelated tool calls in group contexts

### Timeline Features (events generated & stored)

* [+] Gaze-aware object detection now supports foveated cropping, letting the system focus on what the user is actually looking at
* [+] New event bus system enables real-time streaming of timeline events to proactive agents, both from live sessions and historical data
* [+] Proactive agents can now be defined using three strategies: structured parameters, LLM-generated code, or full LLM reasoning loops
* [=] Object detection handles larger batches of images more reliably through chunked DINO inference
* [=] Content text updates now correctly appear in the app and web UI

### System Features (stability & quality)

* [+] Hermetic CI test harness enables reproducible, offline testing of the agent without production infrastructure
* [+] Proactive agent runtime deployed as a standalone thrift server in Tupperware
* [=] Major internal refactor decouples business logic from storage dependencies, enabling faster local development and testing
* [=] Deprecated legacy execution code removed (ConcurrentGraphManager, AriaAIAgentExecutor, PrefetchManager), reducing code complexity
* [-] Removed evidence messages from chat thread queries that were causing duplicated system messages
