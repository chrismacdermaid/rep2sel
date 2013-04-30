# -*- tcl -*-

# +----------------------------------------------------------+
# | A GUI interface to create selections for representations |
# | similar to Pymol                                         |
# +----------------------------------------------------------+

namespace eval ::rep2sel:: {
    namespace export rep2sel

    variable sys
    variable reps
    variable as_lookup

    variable version 1.0

    set sys(OK) 0
    set sys(ERROR) -1
}

proc ::rep2sel::usage {} {

}

proc ::rep2sel::rep2sel { args } {

    variable as_lookup

    set cmd ""

    set newargs {}
    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]

        if {[string match -?* $arg]} {

            set val [lindex $args [expr {$i + 1}]]

            switch -- $arg {
                -on -
                -off
                {on_off $arg; return}

                -clean
                {clean; return}

                -reset
                {veryclean; return}

                -- break

                default {
                    vmdcon -info "default: $arg"
                }
            }
        } else {
            lappend newargs $arg
        }
    }

    set retval ""
    if {[llength $newargs] > 0} {
        set cmd [lindex $newargs 0]
        set newargs [lrange $newargs 1 end]
    } else {
        set newargs {}
        set cmd help
    }

    if { ![string equal $cmd help] } {
    }

    switch -- $cmd {

        make {
            return [make_sel {*}$newargs]
        }

        makemol {
            return [make_sel_mol {*}$newargs]
        }

        delete {
            return [del_sel {*}$newargs]
        }

        get {
            return [get_sel {*}$newargs]
        }

        update {
            return [update_sel {*}$newargs]
        }

        wrap {
            return [sel_wrap {*}$newargs]
        }

        selections {
            parray as_lookup
        }

        help -
        default {
            usage
        }
    }
}

## Make a lookup of all reps in vmd indexed by {molid repid}
proc ::rep2sel::get_reps {{molid "all"}} {

    variable reps

    if {$molid == "all"} {
        set molid [molinfo list]
    }

    foreach x $molid {
        for {set i 0} {$i < [molinfo $x get numreps]} {incr i} {
            lassign [molinfo $x get "{rep $i} {selection $i}"] rep sel
            set reps([list $x $i]) [list $rep $sel]
        }
    }
}

## Return the selection for a particular representation
proc ::rep2sel::get_reptext {molid repidx} {

    variable sys
    variable reps

    if {[array get reps [list $molid $repidx]] == {}} {
        vmdcon -err "No representation: Mol: $molid Repid: $repidx"
        return $sys(ERROR)
    }

    return [lindex $reps([list $molid $repidx]) 1]
}

## Make a selection for a particular molid/repid
## return it to user
proc ::rep2sel::make_sel {molid repidx} {

    variable sys
    variable as_lookup

    ## Make sure the rep array is up to date, this could be expensive
    ## if there are a lot of mols and/or a lot of reps
    get_reps $molid

    ## Get the selection text for a representation
    set seltext [get_reptext $molid $repidx]

    if {$seltext == $sys(ERROR)} {
        return $sys(ERROR)
    }

    ## Check if selection already exists, if it does, just return it
    set as [sel_ok $molid $repidx]
    if {$as == $sys(OK)} {
        return [get_sel $molid $repidx]
    }

    ## Make a selection at the top level
    set as [uplevel #0 [list atomselect top $seltext]]

    ##associate lookup table with selection
    set as_lookup([list $molid $repidx]) $as

    ## Return it to the user
    return $as
}

## Make a selection for EACH representation in a mol
proc ::rep2sel::make_sel_mol { molid } {

    variable sys
    variable as_lookup

    set as_list {}
    for {set i 0} {$i < [molinfo $molid get numreps]} {incr i} {
        lassign [molinfo $molid get "{rep $i} {selection $i}"] rep sel

        ## Keeps reps up to date
        set reps([list $molid $i]) [list $rep $sel]

        ## Check if selection already exists
        set as [sel_ok $molid $i]
        if {$as == $sys(OK)} {
            lappend as_list [get_sel $molid $i]
            continue
        }

        ## Make a selection at the top level
        set as [uplevel #0 [list atomselect top $sel]]

        ##associate lookup table with selection
        set as_lookup([list $molid $i]) $as

        ## append to the list of created selections
        lappend as_list $as
    }

    return $as_list
}

## Delete a selection by molid/repidx
proc ::rep2sel::del_sel {molid repidx} {

    variable sys
    variable as_lookup

    set as [get_sel $molid $repidx]
    if {$as == $sys(ERROR)} {
        return $sys(ERROR)
    }

    unset as_lookup([list $molid $repidx])

    uplevel #0 [list $as delete]
}

## Recreate the selection associated with the representation
proc ::rep2sel::update_sel {molid repidx} {

    variable sys

    if {[del_sel $molid $repidx] == $sys(ERROR)} {
        return $sys(ERROR)
    }

    set as [make_sel $molid $repidx]
    if {$as == $sys(ERROR)} {
        return $sys(ERROR)
    }

    return $as
}

## Return the global atomselect name (atomselectxxx)
proc ::rep2sel::get_sel {molid repidx} {

    variable sys
    variable as_lookup

    if {[array get as_lookup [list $molid $repidx]] == {}} {
        vmdcon -err "No selection for representation: Mol: $molid Repid: $repidx"
        return $sys(ERROR)
    }

    return $as_lookup([list $molid $repidx])
}

## Just check if the selection exists
proc ::rep2sel::sel_ok {molid repidx} {

    variable sys
    variable as_lookup

    if {[array get as_lookup [list $molid $repidx]] == {}} {
        return $sys(ERROR)
    }

    return $sys(OK)
}

## Pass a command to the underlying selection:
## ::rep2sel::sel_wrap molid repid get {x y z}
proc ::rep2sel::sel_wrap {args} {

    variable sys
    lassign $args molid repidx

    set as [get_sel $molid $repidx]
    if {$as == $sys(ERROR)} {
        return $sys(ERROR)
    }

    return [uplevel #0 [list $as {*}[lrange $args 2 end]]]
}

## Cleanup everything
proc ::rep2sel::veryclean { args }  {

    variable sys
    variable as_lookup
    variable reps

    ## Kill all associated selections
    foreach {key value} [array get as_lookup *] {
        catch {uplevel #0 [list $value delete]}
        unset as_lookup($key)
    }

    ## Clear reps array
    foreach {key value} [array get reps *] {
        unset reps($value)
    }

    return $sys(OK)
}

## Cleanup selections that no-longer exist
proc ::rep2sel::clean { args }  {

    variable sys
    variable as_lookup

    ## Kill lookups to selections that have been deleted
    set to_delete {}
    foreach {key value} [array get as_lookup *] {
        if {[catch {uplevel #0 [list $value]} val]} {
            lappend to_delete $as_lookup($key)
        }
    }

    foreach x $to_delete {
        unset as_lookup($x)
    }

    return $sys(OK)
}

interp alias {} rep2sel {} ::rep2sel::rep2sel
package provide rep2sel $::rep2sel::version
