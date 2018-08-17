#! /usr/bin/tclsh


set fd      [ open "/etc/hosts" r ]
set raw     [ read $fd ]
set recs    [ split $raw "\n" ]


foreach line $recs {

   # puts $line

   set c    [ string first {#} $line ]
   if { $c > -1 } {
      set str     [ string trimright [ string range $line 0 [ expr $c - 1] ] ]
   } else {
      set str     $line
   }

   if { [ string length $str ] } {

      set data_fields      [ regexp -all -inline {\S+} $str ]

      set i          -1
      set ip         [ lindex $data_fields [ incr i ] ]
      set fqdn       [ lindex $data_fields [ incr i ] ]
      if { [ llength $data_fields ] > 2 } {
         set name    [ lindex $data_fields [ incr i ] ]
      } else {
         set name    [ lindex [ split $fqdn {.} ] 0 ]
      }

      # puts "'$str' '$data_fields'"
      puts "ip=$ip fqdn=$fqdn name=$name"

   }

}





# vim: syntax=tcl
