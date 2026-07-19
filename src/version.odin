package main

import "core:strings"

MCVersion :: enum {
	V1_8_9,
	V1_21_3,
}

default_mcversion :: proc(ctx: MothCtx) -> MCVersion {
	return ctx == .ElytraSim ? .V1_21_3 : .V1_8_9
}

mcversion_name :: proc(version: MCVersion) -> string {
	switch version {
	case .V1_8_9:
		return "1.8.9"
	case .V1_21_3:
		return "1.21.3"
	}
	return "unknown"
}

parse_mcversion :: proc(value: string) -> (MCVersion, bool) {
	trimmed := strings.trim_space(value)
	switch trimmed {
	case "1.8.9":
		return .V1_8_9, true
	case "1.21.3":
		return .V1_21_3, true
	}
	return {}, false
}

apply_version_defaults :: proc(p: ^Player, version: MCVersion) {
	switch version {
	case .V1_8_9:
		p.inertia_threshold = 0.005
		p.sprint_delay = true
		p.sneak_delay = false
		p.slow_falling = false
	case .V1_21_3:
		p.inertia_threshold = 0.003
		p.sprint_delay = false
		p.sneak_delay = true
	}
}
