// Captures a deterministic grid of state.Apply / state.View input→output pairs
// as test/fixtures/resume_vectors.json, for M1's resume engine to replay as a
// differential oracle.
//
// This is the one thing the live-HTTP capture cannot produce. Apply and View
// are pure functions over a UserState; driving them over HTTP would fold in the
// handler's own validation (an out-of-range file index is a 400 at
// media.go:531, while the engine itself returns the state unchanged) and would
// cost one request and one meta.json read-modify-write per vector.
//
// Not part of this repo's build. It is copied into a clone of upstream at tag
// v0.20.3 as internal/state/capture_state_vectors_test.go and run there —
// see tool/capture-resume-vectors.sh, which does exactly that.
//
// The expectations are not written by hand: whatever the real engine returns is
// what gets recorded. That is the entire value. A hand-written expectation can
// only encode what we already believe.
package state

import (
	"encoding/json"
	"os"
	"testing"
)

type vector struct {
	Name string `json:"name"`
	In   struct {
		Refs     []string `json:"refs"`
		Pointer  *Pointer `json:"pointer"`
		Watched  bool     `json:"watched"`
		File     int      `json:"file"`
		Position float64  `json:"position"`
		Duration float64  `json:"duration"`
	} `json:"in"`
	Out struct {
		Pointer *Pointer `json:"pointer"`
		Watched bool     `json:"watched"`
		View    struct {
			Watched         bool   `json:"watched"`
			ContinueIndex   int    `json:"continueIndex"`
			ContinueSeconds int    `json:"continueSeconds"`
			PerFile         []bool `json:"perFile"`
		} `json:"view"`
	} `json:"out"`
}

// TestCaptureStateVectors is a capture, not an assertion. Run it with
// FILEFIN_VECTORS_OUT set to the destination path; without it, it skips, so a
// stray `go test ./...` in the upstream clone does not write files.
func TestCaptureStateVectors(t *testing.T) {
	out := os.Getenv("FILEFIN_VECTORS_OUT")
	if out == "" {
		t.Skip("FILEFIN_VECTORS_OUT not set")
	}

	// Two ref shapes, because Refs distinguishes them: a single-file folder's
	// ref is "", a numbered episode's is "SxE".
	refSets := map[string][]string{
		"single": Refs([]FileKey{{}}),
		"three":  Refs([]FileKey{{Season: 1, Episode: 1}, {Season: 1, Episode: 2}, {Season: 1, Episode: 3}}),
	}

	// Starting states: absent pointer (curIdx == -1, so the first report on
	// file 0 always installs one), and pointers at each index and offset.
	type start struct {
		name    string
		pointer *Pointer
		watched bool
	}

	// Reports: below / at / above the 0.90 threshold, the degenerate durations
	// that must never count as crossed, a negative position (Go's round clamps
	// to 0), and out-of-range indices.
	reports := []struct {
		file     int
		position float64
		duration float64
	}{
		{0, 0, 100}, {0, 1.4, 100}, {0, 1.5, 100}, {0, 1.6, 100},
		{0, 50, 100}, {0, 89.9, 100}, {0, 90, 100}, {0, 90.1, 100}, {0, 100, 100},
		{0, 10, 0}, {0, 10, -1}, {0, -5, 100}, {0, 0, 0},
		{1, 0, 100}, {1, 50, 100}, {1, 95, 100},
		{2, 0, 100}, {2, 50, 100}, {2, 95, 100}, {2, 100, 100},
		{-1, 50, 100}, {3, 50, 100}, {99, 50, 100},
	}

	var vectors []vector
	for _, setName := range []string{"single", "three"} {
		refs := refSets[setName]

		starts := []start{{name: "none", pointer: nil, watched: false}}
		for i := range refs {
			for _, secs := range []int{0, 45, 90} {
				p := Pointer{File: refs[i], Seconds: secs}
				starts = append(starts,
					start{name: "at" + refs[i] + "@" + itoa(secs), pointer: &p, watched: false})
			}
		}
		starts = append(starts, start{name: "watched", pointer: nil, watched: true})

		for _, s := range starts {
			for _, r := range reports {
				if r.file >= len(refs) && r.file != 99 && r.file != 3 && r.file >= 0 {
					continue
				}
				var ptr *Pointer
				if s.pointer != nil {
					c := *s.pointer
					ptr = &c
				}
				in := UserState{Progress: ptr, Watched: s.watched}
				got := Apply(in, refs, r.file, r.position, r.duration)
				view := View(got, refs)

				var v vector
				v.Name = setName + "/" + s.name + "/f" + itoa(r.file) + "@" +
					ftoa(r.position) + "of" + ftoa(r.duration)
				v.In.Refs = refs
				v.In.Pointer = s.pointer
				v.In.Watched = s.watched
				v.In.File = r.file
				v.In.Position = r.position
				v.In.Duration = r.duration
				v.Out.Pointer = got.Progress
				v.Out.Watched = got.Watched
				v.Out.View.Watched = view.Watched
				v.Out.View.ContinueIndex = view.ContinueIndex
				v.Out.View.ContinueSeconds = view.ContinueSeconds
				v.Out.View.PerFile = view.PerFile
				vectors = append(vectors, v)
			}
		}
	}

	body, err := json.MarshalIndent(struct {
		Source           string   `json:"source"`
		WatchedThreshold float64  `json:"watchedThreshold"`
		Vectors          []vector `json:"vectors"`
	}{"internal/state/engine.go @ v0.20.3 (9399feb)", WatchedThreshold, vectors}, "", "  ")
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if err := os.WriteFile(out, append(body, '\n'), 0o644); err != nil {
		t.Fatalf("write %s: %v", out, err)
	}
	t.Logf("wrote %d vectors to %s", len(vectors), out)
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	if neg {
		return "-" + string(b)
	}
	return string(b)
}

func ftoa(f float64) string {
	b, _ := json.Marshal(f)
	return string(b)
}
