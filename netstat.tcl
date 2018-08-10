#! /usr/bin/tclsh

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# global variables

set debug_run           no
set debug_results       no
set debug_pid_names     no
set debug_categories    yes


# this translates all of the known state names to a TLA
dict set state_names CLOSED            CLD
dict set state_names CLOSE_WAIT        CLW
dict set state_names ESTABLISHED       EST
dict set state_names FIN_WAIT_1        FW1
dict set state_names FIN_WAIT_2        FW2
dict set state_names LAST_ACK          LAK
dict set state_names LISTEN            LIS
dict set state_names SYN_RECEIVED      SYR
dict set state_names SYN_SEND          SYS
dict set state_names TIME_WAIT         TMW

set pid_names [ dict create 0 {---} ]

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

proc print_hdr { hdr } {
   puts "\n"
   puts {===============================================================================}
   puts $hdr
   puts {===============================================================================}
}

proc print_subhdr { subhdr } {
   puts ""
   puts {-------------------------------------------------------------------------------}
   puts $subhdr
}

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# main procedure for gathering netstat data

proc run_netstat {} {

   # step 1 -- define the local variables

   global pid_names
   global state_names
   global debug_run

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
      local_port           \
      remote               \
      sock_state           \
      sock_state_desc      \
      pid_raw              \
      pid_id               \
      pid_key              \
      pid_name             \
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


   # step 2 -- run the command and get the raw output

   # run the command and get the data_raw data
   set netstat_raw         [ run_exe $exe $args ]


   # step 3 -- process and cook the data

   # we want to exclude the header from the actual data
   # set header              [ lindex $netstat_raw 1 ]
   set netstat_data        [ lrange $netstat_raw 2 end ]

   # iterate each line from the data
   foreach data_raw $netstat_data {

      # step 3.1 -- parse the raw data into a proper list and count the number
      # of fields we find

      set data_fields      [ regexp -all -inline {\S+} $data_raw ]
      set fcnt             [ llength $data_raw ]


      # step 3.2 -- skip any blank lines (usually the last one)

      # skip blank lines (usually the last one)
      if { $fcnt == 0 } continue


      # step 3.3 -- now extract the individual fields

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

      set pid_raw          [ lindex $data_fields [ incr i ] ]
      set timer_state      [ lindex $data_fields [ incr i ] ]
      set counts_raw       [ lindex $data_fields [ incr i ] ]


      # step 3.4 -- parse and translate various fields

      # get the local port nubmer
      set local_port       [ lindex [ split $local ":" ] end ]

      # translate the sock_state to a TLA for better display
      if { [ dict exists $state_names $sock_state ] } {
         set sock_state_desc  [ dict get $state_names $sock_state ]
      } else {
         set sock_state_desc  {---}
      }

      # split the pid/program_name field
      if { $pid_raw == "-" } {
         set pid_id        {0}
         set pid_name      {-}
      } else {
         set pid_lst       [ split  $pid_raw {/} ]
         set pid_id        [ lindex $pid_lst 0 ]
         set pid_name      [ lindex $pid_lst 1 ]
      }
      set pid_key          [ mk_pid_key $pid_id $proto ]

      # split out all of the counters
      set counts           [ regexp -all -inline {[^()/]+} $counts_raw ]
      set timer_val        [ lindex $counts 0 ]
      set rexmits          [ lindex $counts 1 ]
      set keepalives       [ lindex $counts 2 ]


      # step 3.5 -- update the dictionary that maps pid_id's to pid_name's

      if { ! [ dict exists $pid_names $pid_id ] } {
         dict set pid_names $pid_id $pid_name
      }


      # step 3.6 -- generate the formatted output

      # TODO: need to generate a formatted output, but probably needs to be
      # deferred until the caller can categorize each record and collapse those
      # we're just counting

      set data_formatted   [ format "%d %s" $fcnt $data_fields ]


      # step 3.7 -- generate the results

      # generate the dictionary for this record
      set d                [ dict create ]
      foreach n $field_names {
         dict append d $n [ get_var $n ]
      }
      # append it to the master list (i.e.: the return result)
      lappend netstat_list $d


      # spiffle

      if { $debug_run } {
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

   # more spiffle
   if { $debug_run } {
      puts {-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-}
   }

   # return he master list, i.e.: a list containing a dictionary for each
   # record in the output

   return $netstat_list
}

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# helper procedure to dump a list of dictionaries containing a netstat record

proc dump_list { list_name } {

   print_subhdr "dumping list: $list_name\n"

   upvar $list_name local_list
   if { [ llength $local_list ] } {
      foreach d $local_list {
         puts [ dict get $d data_fields ]
      }
   } else {
      puts "empty"
   }
}

proc mk_pid_key { pid_id proto } {

   return [ format "%08d,%s" $pid_id $proto ]
}

proc get_pid_id { pid_key } {

   set pid_id              [ string trimleft [ lindex [ split $pid_key "," ] 0 ] 0 ]
   if { ! [ string length $pid_id  ] } {
      set pid_id           0
   }

   return $pid_id
}



####################################################################################################

  # #      #     #    #    ### #     #
  # #      ##   ##   # #    #  ##    #
#######    # # # #  #   #   #  # #   #
  # #      #  #  # #     #  #  #  #  #
#######    #     # #######  #  #   # #
  # #      #     # #     #  #  #    ##
  # #      #     # #     # ### #     #

####################################################################################################


# step 1 -- capture the data

# run netstat and capture the results, returned as a list of dictionaries, each
# of which contains the parsed data record from the raw output of netstat

set netstat_data [ run_netstat ]

# spiffle
if { $debug_results } {
   puts "\nprint main results:"
   foreach d $netstat_data {
      puts {-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-}
      pdict $d
   }
   puts {-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-}
}


# step 2 -- iterate the netstat data, categorize each record and add it to the
# appropriate list

# this is a list of all the categories, i.e.: the name of the list used to
# store records for that category
set categories             [ list netstat_est netstat_syn netstat_wait netstat_closed netstat_listen ]

# these are the individual lists that will contain their respective categories
set netstat_est            [ list ]
set netstat_syn            [ list ]
set netstat_wait           [ list ]
set netstat_closed         [ list ]
set netstat_listen         [ list ]

# anything that doesn't fall in one of the above categories is subject to being
# collapsed into a single output record (with a count); these records are
# stored in a dictionary of lists, based on the pid_key of the record
set netstat_undef          [ dict create ]

# basically, records are organize by their respective sock_state value

# all known socket states:
#
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

   set sock_state          [ dict get $d sock_state ]
   set pid_id              [ dict get $d pid_id ]
   set pid_key             [ dict get $d pid_key ]

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

      default              {
         dict lappend netstat_undef  $pid_key $d
      }
   }
}

# spiffle
if { $debug_pid_names } {
   # dump out the pid to name lookup dictionary
   puts "\n\n"
   puts {--------------------------------------------------------------------------------}
   puts "pid names:"
   pdict $pid_names
   puts {--------------------------------------------------------------------------------}
}

# spiffle
if { $debug_categories } {

   print_hdr "dumping categories"

   # dump each of the categories
   foreach c $categories {
      dump_list $c
   } 

   print_hdr "dumping list: netstat_undef"

   foreach pid_key [ lsort [ dict keys $netstat_undef ] ] {

      set pid_id              [ get_pid_id $pid_key ]
      set d_list              [ dict get $netstat_undef $pid_key ]

      print_subhdr "dumping: ${pid_id}/[ dict get $pid_names $pid_id ] cnt=[ llength $d_list ] key=$pid_key\n"

      foreach d $d_list {
         puts [ dict get $d data_fields ]
      }
   }

}



# vim: syntax=tcl
