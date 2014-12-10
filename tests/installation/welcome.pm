#!/usr/bin/perl -w
use strict;
use base "y2logsstep";
use testapi;

sub run() {
    my $self = shift;

    assert_screen([qw/inst-welcome inst-betawarning linuxrc-repo-not-found/], 500); # live cds can take quite a long time to boot
    # we can't just wait for the needle as the beta popup may appear delayed and we're doomed
    wait_idle 5;
    my $ret = assert_screen [qw/inst-welcome inst-betawarning/], 3;

    if( $ret->{needle}->has_tag("linuxrc-repo-not-found") ) {
        die "installation didn't even start!\n";
    }
    
    #if ( $ret->{needle}->has_tag("inst-betawarning") ) {
    #    send_key "ret";
    #    assert_screen "inst-welcome", 5;
    #}

    if(get_var("BETA")) {
    	assert_screen "inst-betawarning", 5;
    	send_key "ret";
    } elsif (check_screen "inst-betawarning", 2) {
        die "beta warning found in non-beta";
    }

    wait_idle;

    # animated cursor wastes disk space, so it is moved to bottom right corner
    mouse_hide;

    # license+lang
    if ( get_var("HASLICENSE") ) {
        send_key $cmd{"accept"};    # accept license
    }
    assert_screen "languagepicked", 2;
    send_key $cmd{"next"};
    if ( check_screen "langincomplete", 1  ) {
        send_key "alt-f";
    }
}

1;
# vim: set sw=4 et:
