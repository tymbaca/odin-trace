#+vet explicit-allocators
#+private
package trace

import "core:container/queue"
import "base:runtime"
import "core:testing"

@(test)
tracer_test :: proc(t: ^testing.T) {
        context.user_ptr = new(Context_User_Data, context.allocator)

        tracer: Tracer
        init(&tracer, from_context_proc, to_context_proc, context.allocator)
        defer destroy(&tracer)
        defer {
                data := (^Context_User_Data)(context.user_ptr)
                free(data, tracer.allocator)
        }

        set_global_tracer(&tracer)

        foo()

        testing.expect_value(t, len(tracer.spans), 2)
        testing.expect_value(t, queue.len(tracer.export_queue), 2)
}

@(test)
tracer_exporter_test :: proc(t: ^testing.T) {
        context.user_ptr = new(Context_User_Data, context.allocator)

        exporter_impl: Test_Exporter
        exporter := Exporter{
                data = &exporter_impl,
                export = test_exporter_proc,
        }

        tracer: Tracer
        init(&tracer, from_context_proc, to_context_proc, context.allocator, exporter)
        defer destroy(&tracer)
        defer {
                data := (^Context_User_Data)(context.user_ptr)
                free(data, tracer.allocator)
        }

        set_global_tracer(&tracer)

        foo()

        testing.expect_value(t, len(tracer.spans), 0)
        testing.expect_value(t, queue.len(tracer.export_queue), 0)

        testing.expect_value(t, len(exporter_impl.spans), 2)
}

Test_Exporter :: struct {
        spans: [dynamic]Span,
}

test_exporter_proc :: proc(data: rawptr, spans: []Span) -> Exporter_Error {
        e := (^Test_Exporter)(data)
        append(&e.spans, ..spans)
        return nil
}

foo :: proc() {
	span: Span
	context, span = start() // foo
	defer end(span)

	bar(77)
}

bar :: proc(val: int) {
	span: Span
	context, span = start(attrs = {{"val", val}})
	defer end(span)
}

Context_User_Data :: struct {
        current_span: Span,
}

to_context_proc :: proc(ctx: runtime.Context, span: Span) -> runtime.Context {
        ctx := ctx

        data := (^Context_User_Data)(ctx.user_ptr)
        data.current_span = span

        return ctx
}

from_context_proc :: proc(ctx: runtime.Context) -> (Span, bool) {
        if ctx.user_ptr == nil {
                return {}, false
        }

        data := (^Context_User_Data)(ctx.user_ptr)

        return data.current_span, true
}
