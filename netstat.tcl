#! /usr/bin/tclsh

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# global variables

set debug no

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

# helper procedures

proc print_var { var } {
   upvar $var val
   puts [ format "%16s -> %s" $var $val ]
}

proc get_var { var } {
   upvar $var val
   return $val
}

proc run_exe { exe args } {
   set cmdline [ concat |$exe [ join $args ] ]
   set fd [ open "$cmdline" r ]
   set raw [ read $fd ]
   close $fd
   set recs [ split $raw "\n" ]
   return $recs
}

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# main procedure for gathering netstat data

proc run_netstat {} {

   # this is the list of fields that will be added to the dictionary
   set field_names [ list  \
      data_raw             \
      data_fields          \
      data_formatted       \
      fcnt                 \
      proto                \
      recvq                \
      sendq                \
      local                \
      remote               \
      sock_state           \
      program              \
      timer_state          \
      counts_raw           \
      counts               \
      timer_val            \
      rexmits              \
      keepalives           \
      ]

   # define the command to execute
   set exe                 netstat
   set args                [ list --all --udp --tcp --program --timers ]

   # run the command and get the data_raw data
   set netstat_raw         [ run_exe $exe $args ]

   # we want to exclude the header from the actual data
   # set header              [ lindex $netstat_raw 1 ]
   set netstat_data        [ lrange $netstat_raw 2 end ]

   # iterate each line from the data
   foreach data_raw $netstat_data {

      # parse the raw data into a proper list and count the number of fields we find
      set data_fields      [ regexp -all -inline {\S+} $data_raw ]
      set fcnt             [ llength $data_raw ]

      # skip blank lines (usually the last one)
      if { $fcnt == 0 } continue

      # now extract the individual fields

      set i                -1
      set proto            [ lindex $data_fields [ incr i ] ]
      set recvq            [ lindex $data_fields [ incr i ] ]
      set sendq            [ lindex $data_fields [ incr i ] ]
      set local            [ lindex $data_fields [ incr i ] ]
      set remote           [ lindex $data_fields [ incr i ] ]

      # most udp sockets do *NOT* show a sock_state
      if { $fcnt == 8 } {
         set sock_state    "-"
      } elseif { $fcnt == 9 } {
         set sock_state    [ lindex $data_fields [ incr i ] ]
      }

      set program          [ lindex $data_fields [ incr i ] ]
      set timer_state      [ lindex $data_fields [ incr i ] ]

      # parse the actual timers
      set counts_raw       [ lindex $data_fields [ incr i ] ]
      set counts           [ regexp -all -inline {[^()/]+} $counts_raw ]
      set timer_val        [ lindex $counts 0 ]
      set rexmits          [ lindex $counts 1 ]
      set keepalives       [ lindex $counts 2 ]

      # TODO: need to generate a formated output, but probably needs to be
      # deferred until the caller can categorize each record and collapse those
      # we're just counting
      set data_formatted   [ format "%d %s" $fcnt $data_fields ]

      # generate the dictionary for this record
      set d                [ dict create ]
      foreach n $field_names {
         dict append d $n [ get_var $n ]
      }

      # append it to the master list (i.e.: the return result)
      lappend netstat_list $d

      # debug spiffle
      if { $::debug } {
         puts {-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-}
         puts $data_formatted
         puts "\nprint fields:"
         foreach n $field_names {
            print_var $n
         }
         puts "\nprint dictionary:"
         pdict $d
      }
   }

   # more debug spiffle
   if { $::debug } {
      puts {-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-}
   }

   # return he master list, i.e.: a list containing a dictionary for each
   # record in the output
   return $netstat_list
}

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# run the main procedure and puke out the data

set netstat_data [ run_netstat ]

if { $debug } {
   puts "\nprint main results:"
   foreach d $netstat_data {
      puts {-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-}
      pdict $d
   }
   puts {-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-}
}



# iterate the netstat data and send them to lists based on sock_state

set netstat_est      [ list ]
set netstat_syn      [ list ]
set netstat_wait     [ list ]
set netstat_closed   [ list ]
set netstat_listen   [ list ]
set netstat_undef    [ list ]

# organize them by sock_state
#    CLOSED
#    CLOSE_WAIT
#    ESTABLISHED
#    FIN_WAIT_1
#    FIN_WAIT_2
#    LAST_ACK
#    LISTEN
#    SYN_RECEIVED
#    SYN_SEND
#    TIME_WAIT

foreach d $netstat_data {

   set sock_state [ dict get $d sock_state ]
   puts $sock_state

   switch -glob $sock_state {

      ESTABLISHED          { lappend netstat_est      $d }

      SYN_SEND             -
      SYN_RECEIVED         { lappend netstat_syn      $d }

      CLOSE_WAIT           -
      FIN_WAIT_1           -
      FIN_WAIT_2           -
      LAST_ACK             -
      TIME_WAIT            { lappend netstat_wait     $d }

      CLOSED               { lappend netstat_closed   $d }

      LISTEN               { lappend netstat_listen   $d }

      default              { lappend netstat_undef    $d }
   }
}


proc print_list { list_name } {
   puts "\n"
   puts {-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-}
   puts "dumping list: $list_name\n"
   upvar $list_name local_list
   if { [ llength $local_list ] } {
      foreach d $local_list {
         set data_fields [ dict get $d data_fields ]
         puts $data_fields
      }
   } else {
      puts "empty"
   }
}


set categories             [ list netstat_est netstat_syn netstat_wait netstat_closed netstat_listen netstat_undef ]

foreach c $categories {
   print_list $c
} 





# vim: syntax=tcl
