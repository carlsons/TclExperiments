#! /usr/bin/tclsh

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# leveraged procedures

# dictionary pretty printer
# copied from: http://wiki.tcl.tk/23526
proc pdict { d {i 0} {p "  "} {s " -> "} } {
    set fRepExist [expr {0 < [llength\
            [info commands tcl::unsupported::representation]]}]
    if { (![string is list $d] || [llength $d] == 1)
            && [uplevel 1 [list info exists $d]] } {
        set dictName $d
        unset d
        upvar 1 $dictName d
        puts "dict $dictName"
    }
    if { ! [string is list $d] || [llength $d] % 2 != 0 } {
        return -code error  "error: pdict - argument is not a dict"
    }
    set prefix [string repeat $p $i]
    set max 0
    foreach key [dict keys $d] {
        if { [string length $key] > $max } {
            set max [string length $key]
        }
    }
    dict for {key val} ${d} {
        puts -nonewline "${prefix}[format "%-${max}s" $key]$s"
        if {    $fRepExist && [string match "value is a dict*"\
                    [tcl::unsupported::representation $val]]
                || ! $fRepExist && [string is list $val]
                    && [llength $val] % 2 == 0 } {
            puts ""
            pdict $val [expr {$i+1}] $p $s
        } else {
            puts "'${val}'"
        }
    }
    return
}

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-


set hosts   [ dict create ]

set fd      [ open "/etc/hosts" r ]
set raw     [ read $fd ]
set recs    [ split $raw "\n" ]

foreach rec $recs {

   # puts $rec

   # find the comment marker in the record
   set c                   [ string first {#} $rec ]
   # strip the comment and trailing space from the record
   if { $c > -1 } {
      set str              [ string trimright [ string range $rec 0 [ expr $c - 1] ] ]
   } else {
      set str              $rec
   }

   # and process this record, if there's anything left
   if { [ string length $str ] } {

      # split the fields into a list of 2 or 3 elements: ip, fqdn and name
      set data_fields      [ regexp -all -inline {\S+} $str ]

      # extract the fields from the list
      set i                -1
      set ip               [ lindex $data_fields [ incr i ] ]
      set fqdn             [ lindex $data_fields [ incr i ] ]
      if { [ llength $data_fields ] > 2 } {
         set name          [ lindex $data_fields [ incr i ] ]
      } else {
         set name          [ lindex [ split $fqdn {.} ] 0 ]
      }

      # puts "'$str' '$data_fields'"
      # puts "ip=$ip fqdn=$fqdn name=$name"

      set d                [ dict create ]

      dict set d           fqdn  $fqdn
      dict set d           name  $name

      dict set hosts       $ip   $d

   }

}


pdict $hosts

puts "\n\nlookup=[ dict get $hosts 127.0.0.1 fqdn ]"


# vim: syntax=tcl
