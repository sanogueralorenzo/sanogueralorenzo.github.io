#ifndef CREST_ENGINE_H
#define CREST_ENGINE_H

/* The engine contract. An engine binding registers with an app, the core
 * hands it commands (CreatePage, LoadPage, ClosePage) and the binding reports
 * what happens to its pages (PageCreated, PageCreationFailed, PageClosed, the
 * navigation events and PageStateChanged, at most once per page per turn).
 * While its engine waits, a binding may also ask the core a question about one
 * of its pages (LinkActivation), which the core answers at once from its state
 * without changing it. Registrations, commands, reports, questions and answers
 * cross in the same generated wire format as crest_app.h; crest_contracts.h
 * names the EngineCommand, EngineEvent and EngineQuestion tags and the engine
 * contract's own fingerprint, which changes only when the engine contract
 * does.
 *
 * The core delivers commands in the order it issued them, never while it holds
 * a lock and never on the stack of the report that caused them: an intent or a
 * report that arrives while a command is being run only adds to the queue,
 * and the call already delivering runs it next. A command issued by
 * crest_app_dispatch has been delivered when the dispatch returns, unless the
 * dispatch itself runs inside a delivery.
 */
#include "crest_app.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Reports one encoded EngineEvent: crest_engine_report itself. */
typedef crest_status_t (CREST_CALL *crest_engine_report_t)(uint64_t app, uint64_t engine, const uint8_t* event, size_t length);

/* Receives the encoded answer to an engine question, borrowed for the call,
 * with the context the question was asked with. */
typedef void (CREST_CALL *crest_engine_answer_t)(void* context, const uint8_t* answer, size_t length);

/* Asks one encoded EngineQuestion: crest_engine_ask itself. */
typedef crest_status_t (CREST_CALL *crest_engine_ask_t)(uint64_t app, uint64_t engine, const uint8_t* question, size_t length,
    crest_engine_answer_t answer, void* context);

/* A binding's function table, copied at registration. context is the
 * binding's own and comes back with every call. attach, which may be NULL,
 * runs once when registration succeeds, before crest_engine_register returns,
 * with the engine's handle and the functions to report and ask through. run
 * receives one encoded EngineCommand; the bytes are borrowed for the call. */
typedef struct {
    void* context;
    void (CREST_CALL *attach)(void* context, uint64_t app, uint64_t engine, crest_engine_report_t report,
        crest_engine_ask_t ask);
    void (CREST_CALL *run)(void* context, const uint8_t* command, size_t length);
} crest_engine_binding_t;

/* The platform's direct path to a binding: what the UI asks of a page's engine
 * itself (EnginePage), view work that changes no browser state. The core never
 * calls it; a binding written outside the platform's language hands it to the
 * platform beside its binding table.
 *
 * request receives one encoded PageRequest, borrowed for the call, and answers
 * OK with the request's encoded answer in out, which release frees, or
 * INVALID_MESSAGE for bytes that do not decode. present_to names where the
 * binding sends each encoded EnginePresentation, with ui handed back; NULL
 * stops them. A binding presents on the thread that makes requests, never on
 * the stack of a request or of one of its engine's own callbacks. */
typedef void (CREST_CALL *crest_engine_present_t)(void* ui, const uint8_t* presentation, size_t length);
typedef struct {
    void* context;
    crest_status_t (CREST_CALL *request)(void* context, const uint8_t* request, size_t length, crest_buffer_t* out);
    void (CREST_CALL *release)(void* context, crest_buffer_t* buffer);
    void (CREST_CALL *present_to)(void* context, crest_engine_present_t present, void* ui);
} crest_engine_pages_t;

/* registration is one encoded EngineRegistration. VERSION_MISMATCH when the
 * fingerprint is not this core's engine contract. REJECTED: out_rejection
 * holds one rejection (EngineLacksCapability, EngineAlreadyRegistered,
 * DefaultEngineAlreadyRegistered). INVALID_HANDLE for an app that is gone. */
CREST_API crest_status_t CREST_CALL crest_engine_register(uint64_t app, const uint8_t* fingerprint, size_t fingerprint_length,
    const uint8_t* registration, size_t registration_length, const crest_engine_binding_t* binding,
    uint64_t* out_engine, crest_buffer_t* out_rejection);
/* Never refused: OK for a report about a page the core no longer knows.
 * INVALID_MESSAGE for bytes that do not decode, INVALID_HANDLE for an engine
 * this app did not register. What the report changed arrives through
 * crest_app_drain. */
CREST_API crest_status_t CREST_CALL crest_engine_report(uint64_t app, uint64_t engine, const uint8_t* event, size_t length);
/* Answers one encoded EngineQuestion at once: OK after answer ran once with
 * the encoded answer, which changes nothing in the core. A binding asks while
 * its engine waits, on the thread that runs its commands. INVALID_MESSAGE for bytes
 * that do not decode, INVALID_HANDLE for an engine this app did not register;
 * answer does not run for either. */
CREST_API crest_status_t CREST_CALL crest_engine_ask(uint64_t app, uint64_t engine, const uint8_t* question, size_t length,
    crest_engine_answer_t answer, void* context);
/* The binding hears nothing more once this returns on the thread that runs
 * its commands; commands still queued for it are dropped. Destroying the app
 * unregisters every binding. */
CREST_API crest_status_t CREST_CALL crest_engine_unregister(uint64_t app, uint64_t engine);

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif /* CREST_ENGINE_H */
