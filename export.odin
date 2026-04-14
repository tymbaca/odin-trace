#+vet explicit-allocators
#+private
package trace

import "core:net"
import "core:time"
import "base:runtime"
import "core:container/queue"
import "core:sync"
import "core:thread"

start_exporting :: proc(tracer: ^Tracer) {
        tracer.exporter_thread = thread.create_and_start_with_poly_data(tracer, listen_and_export)
}

stop_exporting :: proc(tracer: ^Tracer) {
        sync.auto_reset_event_signal(&tracer.export_queue_cond)
        thread.join(tracer.exporter_thread.?)
}

append_to_export :: proc(tracer: ^Tracer, span: Span) {
        queue.push_back(&tracer.export_queue, span)
        sync.auto_reset_event_signal(&tracer.export_queue_cond)
}

listen_and_export :: proc(tracer: ^Tracer) {
        for {
                spans, must_exit := wait_and_dequeue(tracer, tracer.allocator)
                if must_exit {
                        return
                }

                if err := tracer.exporter->export(spans); err != nil {
                        for span in spans {
                                queue.push_front(&tracer.export_queue, span)
                        }
                }
        }
}

wait_and_dequeue :: proc(tracer: ^Tracer, allocator: runtime.Allocator) -> (spans: []Span, must_exit: bool) {
        sync.auto_reset_event_wait(&tracer.export_queue_cond)
        if tracer.state != .Normal {
                return nil, true
        }

        spans_dyn := make([dynamic]Span, 0, queue.len(tracer.export_queue), allocator)
        for span in queue.pop_front_safe(&tracer.export_queue) {
                append(&spans_dyn, span)
        }

        return spans_dyn[:], false
}
