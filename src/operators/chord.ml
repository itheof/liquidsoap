(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2010 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 *****************************************************************************)

open Source

let chan = 0

(* TODO: bemol and sharp *)
let note_of_string = function
  | "A" -> 69
  | "B" -> 71
  | "C" -> 72
  | "D" -> 74
  | "E" -> 76
  | "F" -> 77
  | "G" -> 79
  | _ -> assert false
let note_of_string s = note_of_string s - 12

class chord ~kind (source:source) =
object (self)
  inherit operator kind [source] as super

  method stype = source#stype

  method remaining = source#remaining

  method is_ready = source#is_ready

  method abort_track = source#abort_track

  val mutable notes_on = []

  method private get_frame buf =
    let offset = MFrame.position buf in
    source#get buf;
    let m = MFrame.content buf offset in
    let meta = MFrame.get_all_metadata buf in
    let chords =
      let ans = ref [] in
        List.iter
          (fun (t,m) ->
             if t >= offset then
               List.iter
                 (fun c ->
                    try
                      let sub = Pcre.exec ~pat:"^([A-G])(|M|m|M7|m7|dim)$" c in
                      let n = Pcre.get_substring sub 1 in
                      let n = note_of_string n in
                      let m = Pcre.get_substring sub 2 in
                        ans := (t,n,m) :: !ans
                    with
                      | Not_found ->
                          self#log#f 3 "Could not parse chord '%s'." c
                 ) (Hashtbl.find_all m "chord")
          ) meta;
        List.rev !ans
    in
    let play t n =
      let notes = List.map (fun n -> t, Midi.Note_on (n,1.)) n in
        m.(chan) := notes @ !(m.(chan));
        notes_on <- n @ notes_on
    in
    let mute t =
      let notes = List.map (fun n -> t, Midi.Note_off (n,1.)) notes_on in
        m.(chan) := notes @ !(m.(chan));
        notes_on <- []
    in
      List.iter
        (fun (t,c,m) -> (* time, base, mode *)
           (* Negative base note means mute. *)
           if c >= 0 then
             (
               match m with
                 | "" | "M" -> (* major *)
                     play t [c;c+4;c+7]
                 | "m" -> (* minor *)
                     play t [c;c+3;c+7]
                 | "7" ->
                     play t [c;c+4;c+7;c+10]
                 | "M7" ->
                     play t [c;c+4;c+7;c+11]
                 | "m7" ->
                     play t [c;c+3;c+7;c+10]
                 | "dim" ->
                     play t [c;c+3;c+6]
                 | m ->
                     self#log#f 5 "Unknown mode: %s\n%!" m
             );
           (* It's important to call this after because we want to mute before
            * playing the new chord. *)
           mute t
        ) chords;
      m.(chan) := Mutils.sort_track !(m.(chan))
end

let () =
  let in_k =
    let z = Frame.Zero in
      Lang.kind_type_of_frame_kind {Frame.audio=z;video=z;midi=z}
  in
  let out_k =
    Lang.kind_type_of_kind_format ~fresh:1 (Lang.any_fixed_with ~midi:1 ())
  in
  Lang.add_operator "midi.chord"
    [
      "", Lang.source_t in_k, None, None
    ]
    ~kind:(Lang.Unconstrained out_k)
    ~category:Lang.MIDIProcessing
    ~descr:"Generate a chord."
    (fun p kind ->
       let f v = List.assoc v p in
       let src = Lang.to_source (f "") in
         new chord ~kind src)