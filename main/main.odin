#+vet explicit-allocators
package main

import "core:fmt"
import "base:runtime"
import ".."

main :: proc() {
	foopath()
}

foopath :: proc(loc := #caller_location) {
        fmt.println(loc.procedure)
}

foo :: proc() {
	span: trace.Span
	context, span = trace.start("foo")
	defer trace.end(span)

	bar(77)
}

bar :: proc(val: int) {
	span: trace.Span
	context, span = trace.start("bar", {{"val", val}})
	defer trace.end(span)
}
