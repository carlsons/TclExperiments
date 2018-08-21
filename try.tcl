#! /usr/bin/tclsh

set debug   no
set verbose no

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



####################################################################################################


 ####  ###### #####           ##   #####  #####  #####   ####
#    # #        #            #  #  #    # #    # #    # #
#      #####    #           #    # #    # #    # #    #  ####
#  ### #        #           ###### #    # #    # #####       #
#    # #        #           #    # #    # #    # #   #  #    #
 ####  ######   #           #    # #####  #####  #    #  ####
                    #######
####################################################################################################

proc get_ipv { ip } {
   if { [ string first "." $ip ] > -1 } {
      return 4
   }
   if { [ string first ":" $ip ] > -1 } {
      return 6
   }

   return -code error "ip not recognizable: '$ip'"
}

proc compare_ips { lval rval } {

   # determine if each is an IPv4 or IPv6 addr
   set lver    [ get_ipv $lval ]
   set rver    [ get_ipv $rval ]

   # handle different versions; IPv4 is always less than an IPv6
   if { $lver != $rver } {
      if { $lver == 4 } {
         return -1
      }
      return 1
   }

   # handle IPv4 addresses; do a more sensible numeric comparison
   if { $lver == 4 } {
      set llst    [ split $lval "." ]
      set rlst    [ split $rval "." ]
      foreach lv $llst rv $rlst {
         if { $lv < $rv } {
            puts [ format "DEBUG: %-16s %2s %-16s" $lval < $rval ]
            return -1
         }
         if { $lv > $rv } {
            puts [ format "DEBUG: %-16s %2s %-16s" $lval > $rval ]
            return 1
         }
      }
      puts [ format "DEBUG: %-16s %2s %-16s" $lval == $rval ]
      return 0
   }

   # handle IPv6 addresses
   if { $lver == 6 } {
      # TODO: support IPv6 addresses better
      return string compare $lval $rval
   }

   return -code error "coding error"
}


# this is a helper procedure that gets a list of ip addresses by parsing the
# output of netstat

proc get_addrs {} {

   set fd                  [ open "|netstat --tcp -n --wide" r ]
   set raw                 [ read $fd ]
   set recs                [ split $raw "\n" ]

   set rc                  [ dict create ]

   foreach rec [ lrange $recs 2 end ] {

      if { [ string length $rec ] } {

         # field 4 is the ip address and port of the remote socket
         set ip_port          [ lindex [ regexp -all -inline {\S+} $rec ] 4   ]

         # find the last separator; handles both IPv4 and IPv6 addresses
         set sep              [ string last ":" $ip_port                      ]
         set ip               [ string range    $ip_port 0 [ expr $sep - 1 ]  ]

         dict incr rc         $ip

         if { $::debug } {
            puts "----------------------------------------"
            puts "DEBUG: rec=$rec"
            puts "DEBUG: ip_port=$ip_port"
            puts "DEBUG: sep=$sep"
            puts "DEBUG: ip=$ip"
         }

      }
   }

   # return [ lsort -command compare_ips [ dict keys $rc ] ]
   return [ dict keys $rc ]
}



####################################################################################################


#####  ######   ##   #####          #    #  ####   ####  #####  ####
#    # #       #  #  #    #         #    # #    # #        #   #
#    # #####  #    # #    #         ###### #    #  ####    #    ####
#####  #      ###### #    #         #    # #    #      #   #        #
#   #  #      #    # #    #         #    # #    # #    #   #   #    #
#    # ###### #    # #####          #    #  ####   ####    #    ####
                            #######
####################################################################################################


set hosts                     [ dict create ]

proc read_hosts {} {

   global hosts

   set fd                     [ open "/etc/hosts" r ]
   set raw                    [ read $fd ]
   set recs                   [ split $raw "\n" ]

   foreach rec $recs {

      # find the comment marker in the record
      set c                   [ string first {#} $rec ]
      # strip the comment and trailing space from the record
      if { $c > -1 } {
         set data_str         [ string trimright [ string range $rec 0 [ expr $c - 1] ] ]
         set comment          [ string range $rec $c end ]
      } else {
         set data_str         $rec
         set comment          {}
      }

      # and process this record, if there's anything left
      if { [ string length $data_str ] } {

         # split the fields into a list of 2 or 3 elements: ip, fqdn and name
         set data_fields      [ regexp -all -inline {\S+} $data_str ]

         # extract the fields from the list
         lassign $data_fields ip fqdn name
         if { ! [ string length $name ] } {
            set name          [ lindex [ split $fqdn {.} ] 0 ]
         }

         set d                [ dict create ]

         dict set d           record            $rec
         dict set d           data_str          $data_str
         dict set d           data_fields       $data_fields
         dict set d           comment           $comment
         dict set d           ip                $ip
         dict set d           fqdn              $fqdn
         dict set d           name              $name

         dict set hosts       $ip               $d
      }
   }

   close $fd

   return $hosts
}



####################################################################################################


#       ####   ####  #    # #    # #####          #####  #    #  ####          #    #   ##   #    # ######
#      #    # #    # #   #  #    # #    #         #    # ##   # #              ##   #  #  #  ##  ## #
#      #    # #    # ####   #    # #    #         #    # # #  #  ####          # #  # #    # # ## # #####
#      #    # #    # #  #   #    # #####          #    # #  # #      #         #  # # ###### #    # #
#      #    # #    # #   #  #    # #              #    # #   ## #    #         #   ## #    # #    # #
######  ####   ####  #    #  ####  #              #####  #    #  ####          #    # #    # #    # ######
                                          #######                      #######
####################################################################################################


set dns_cache [ dict create ]

proc lookup_dns_name { ip } {

   global dns_cache

   if { $::debug } {
      puts "\n----------------------------------------"
      puts "DEBUG: looking up: $ip\n"
   }

   set fd                  [ open "|host $ip" r ]
   set raw                 [ read $fd ]
   set recs                [ split $raw "\n" ]
   set names               [ list ]

   foreach rec $recs {

      if { [ string length $rec ] > 0 } {
         if { [ string first "domain name pointer" $rec ] > -1 } {

            set data_fields      [ regexp -all -inline {\S+} $rec ]
            set fqdn             [ string trimright [ lindex $data_fields end ] "." ]
            lappend names $fqdn

            if { $::debug } {
               puts "DEBUG: rec=$rec"
               puts "DEBUG: fqdn=$fqdn"
               puts ""
            }

         } else {
            if { $::debug } {
               puts "DEBUG: not found"
            }
         }
      } else {
         if { $::debug } {
            puts "DEBUG: empty"
         }
      }
   }

   if { $::debug && [ llength $names ] } {
      puts "DEBUG: names=$names"
   }

   set err                 [ catch { close $fd } errmsg opts ]


   set dns_entry           [ dict create ]
   dict set dns_entry      ip $ip

   if { $err } {

      dict set dns_entry   found no
      dict set dns_entry   fqdn  "---"
      dict set dns_entry   names [ list "---" ]

      if { $::debug } {
         if { $::verbose } {
            puts "DEBUG: err=$err errmsg=$errmsg"
            pdict $opts
         } else {
            puts "DEBUG: lookup failed"
         }
      }

   } else {

      dict set dns_entry   found yes
      dict set dns_entry   fqdn  [ lindex $names 0 ]
      dict set dns_entry   names $names

   }

   dict set dns_cache      $ip $dns_entry

}



####################################################################################################


#       ####   ####  #    # #    # #####          #    #   ##   #    # ######
#      #    # #    # #   #  #    # #    #         ##   #  #  #  ##  ## #
#      #    # #    # ####   #    # #    #         # #  # #    # # ## # #####
#      #    # #    # #  #   #    # #####          #  # # ###### #    # #
#      #    # #    # #   #  #    # #              #   ## #    # #    # #
######  ####   ####  #    #  ####  #              #    # #    # #    # ######
                                          #######
####################################################################################################


proc lookup_name { ip } {

   global hosts
   global dns_cache

   if {        [ dict exists  $hosts      $ip      ] } {
      return   [ dict get     $hosts      $ip fqdn ]
   }

   if {        [ dict exists  $dns_cache  $ip      ] } {
      return   [ dict get     $dns_cache  $ip fqdn ]
   }

   lookup_dns_name $ip

   if {      ! [ dict exists  $dns_cache  $ip      ] } {
      return -code error "lookup_dns_name failed?"
   }

   return      [ dict get     $dns_cache  $ip fqdn ]
}



####################################################################################################

####### #######  #####  #######     #####  ####### ######  #######
   #    #       #     #    #       #     # #     # #     # #
   #    #       #          #       #       #     # #     # #
   #    #####    #####     #       #       #     # #     # #####
   #    #             #    #       #       #     # #     # #
   #    #       #     #    #       #     # #     # #     # #
   #    #######  #####     #        #####  ####### ######  #######

####################################################################################################


puts "\n-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
puts "\n PARSING /etc/hosts\n"

read_hosts

pdict $hosts
puts "\n\nlookup=[ dict get $hosts 127.0.0.1 fqdn ]"



puts "\n-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
puts "\nGETTING SAMPLE DATA\n"

set inputs                 [ get_addrs ]

lappend inputs 172.217.1.132
lappend inputs 192.168.1.104
lappend inputs 127.0.0.1

set inputs                 [ lsort -command compare_ips $inputs ]


puts "\n-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
puts "\nDEBUG: DOING LOOKUP\n"

foreach ip $inputs {
   set fqdn                [ lookup_name $ip ]
   puts "$ip -> $fqdn"
}



puts "\n-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
puts "\nDEBUG: dumping dns_cache\n"

pdict $dns_cache



# vim: syntax=tcl si
