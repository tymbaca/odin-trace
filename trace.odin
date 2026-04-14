#+vet explicit-allocators
package trace

import "base:runtime"
import "core:encoding/uuid"
import "core:slice"
import "core:time"

@(private)
global_tracer := Tracer{} // noop by default

init :: proc(
	tracer: ^Tracer,
	from_context_proc: proc(ctx: runtime.Context) -> (Span, bool),
	to_context_proc: proc(ctx: runtime.Context, span: Span) -> runtime.Context,
	allocator: runtime.Allocator,
	exporter: Exporter = {},
) {
	tracer.from_context_proc = from_context_proc
	tracer.to_context_proc = to_context_proc
	tracer.allocator = allocator
	tracer.exporter = exporter

	if tracer.exporter != {} {
		start_exporting(tracer^)
	}
}

destroy :: proc(tracer: Tracer) {
	if tracer.exporter != {} {
		stop_exporting(tracer)
	}
}

set_global_tracer :: proc(tracer: Tracer) {
	global_tracer = tracer
}

Tracer :: struct {
	set:               bool,
	from_context_proc: proc(ctx: runtime.Context) -> (Span, bool),
	to_context_proc:   proc(ctx: runtime.Context, span: Span) -> runtime.Context,
	allocator:         runtime.Allocator,
	exporter:          Exporter,
}

Exporter :: struct {
	data:   rawptr,
	export: proc(data: rawptr, spans: []Span) -> Exporter_Error,
}

Exporter_Error :: enum {
	None,
}

Span :: struct {
	id:      uuid.Identifier,
	trace:   uuid.Identifier,
	parent:  uuid.Identifier, // zero if this is a root span
	status:  Span_Status,
	started: time.Time,
	ended:   time.Time, // zero until span is ended
	attrs:   [dynamic]Key_Attribute,
}

Key_Attribute :: struct {
	key:  string,
	attr: Attribute,
}

Attribute :: union {
	string,
	int,
	f64,
}

Span_Status :: enum {
	Unset = 0,
	Ok    = 1,
	Error = 2,
}

start :: proc(
	name: string = "",
	attrs: []Key_Attribute = {},
	tracer := global_tracer,
	loc := #caller_location,
) -> (
	runtime.Context,
	Span,
) {
	if !tracer.set {
		return context, {}
	}

	name := name
	if name == "" {
		name = loc.procedure
	}

	new_span: Span
	new_span.started = time.now()
	new_span.status = .Unset

	if len(attrs) > 0 {
		new_span.attrs = make([dynamic]Key_Attribute, len(attrs), tracer.allocator)
		copy(new_span.attrs[:], attrs)
	}

	parent_span, ok := tracer.from_context_proc(context)
	if ok {
		new_span.trace = parent_span.trace
		new_span.parent = parent_span.id
	} else {
		new_span.trace = uuid.generate_v7()
		new_span.parent = {}
	}

	set_span(tracer, new_span)
	ctx := tracer.to_context_proc(context, new_span)

	return ctx, new_span
}

end :: proc(span: Span, tracer := global_tracer, loc := #caller_location) {
	if span.id == {} {
		return
	}

	lock_span(tracer, span.id)
	defer unlock_span(tracer, span.id)

	span := get_span(tracer, span.id)
	span.ended = time.now()
	set_span(tracer, span)
}

set_attrs :: proc(span: Span, attrs: []Key_Attribute, tracer := global_tracer) {
	if span.id == {} {
		return
	}

	if len(attrs) == 0 {
		return
	}

	lock_span(tracer, span.id)
	defer unlock_span(tracer, span.id)
	span := get_span(tracer, span.id)

	if span.attrs == nil {
		span.attrs = make([dynamic]Key_Attribute, 0, len(attrs), tracer.allocator)
	}


	new_attrs := span.attrs
	for kv in attrs {
		for existing_attr, i in span.attrs {
			if kv.key == existing_attr.key {
				new_attrs[i] = kv
			} else {
				append(&new_attrs, kv)
			}
		}
	}
	span.attrs = new_attrs

	set_span(tracer, span)
}

@(private)
get_tracer :: proc() -> Tracer {
	return global_tracer
}

@(private)
lock_span :: proc(tracer: Tracer, id: uuid.Identifier) {
}

@(private)
unlock_span :: proc(tracer: Tracer, id: uuid.Identifier) {
}

@(private)
get_span :: proc(tracer: Tracer, id: uuid.Identifier) -> Span {
	unimplemented()
}

@(private)
set_span :: proc(tracer: Tracer, span: Span) {
	unimplemented()
}
