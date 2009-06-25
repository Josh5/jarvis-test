###############################################################################
# Description:  Performs a custom <exec> dataset defined in the <app_name>.xml
#               file for this application.  A good example of this would be
#               an exec dataset which handed off to a report script like
#               javis.
#
# Licence:
#       This file is part of the Jarvis WebApp/Database gateway utility.
#
#       Jarvis is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 3 of the License, or
#       (at your option) any later version.
#
#       Jarvis is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with Jarvis.  If not, see <http://www.gnu.org/licenses/>.
#
#       This software is Copyright 2008 by Jonathan Couper-Smartt.
###############################################################################
#
use strict;
use warnings;

use MIME::Types;

package Jarvis::Exec;

use Jarvis::Config;
use Jarvis::Error;
use Jarvis::Text;

################################################################################
# Shows our current connection status.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               xml
#               cgi
#
#       $dataset_name - Name of the special "exec" dataset we are requested to perform.
#
#       $rest_args_aref - A ref to our REST args (slash-separated after dataset)
#
# Returns:
#       0 if the dataset is not a known "exec" dataset
#       1 if the dataset is known and successful
#       die on error attempting to perform the dataset
################################################################################
#
sub do {
    my ($jconfig, $dataset, $rest_args_aref) = @_;

    ###############################################################################
    # See if we have any extra "exec" dataset for this application.
    ###############################################################################
    #
    my $allowed_groups = undef;         # Access groups permitted, or "*" or "**"
    my $command = undef;                # Command to exec.
    my $add_headers = undef;            # Should we add headers.
    my $default_filename = undef;       # A default return filename to use.
    my $filename_parameter = undef;     # Which CGI parameter contains our filename.

    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    if ($axml->{'exec'}) {
        foreach my $exec (@{ $axml->{'exec'} }) {
            next if ($dataset ne $exec->{'dataset'}->content);
            &Jarvis::Error::debug ($jconfig, "Found matching custom <exec> dataset '$dataset'.");

            $allowed_groups = $exec->{'access'}->content || die "No 'access' defined for exec dataset '$dataset'";
            $command = $exec->{'command'}->content || die "No 'command' defined for exec dataset '$dataset'";
            $add_headers = defined ($Jarvis::Config::yes_value {lc ($exec->{'add_headers'}->content || "no")});
            $default_filename = $exec->{'default_filename'}->content;
            $filename_parameter = $exec->{'filename_parameter'}->content;
        }
    }

    # If no match, that's fine.  Just say we couldn't do it.
    $command || return 0;

    # Check security.
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{'status'} = "401 Unauthorized";
        die "Wanted exec access: $failure";
    }

    # Get our parameters.  Note that our special variables like __username will
    # override sneaky user-supplied values.
    #
    my %param_values = $jconfig->{'cgi'}->Vars;

    # Figure out a filename.  It's not mandatory, if we don't have a default
    # filename and we don't have a filename_parameter supplied and defined then
    # we will return anonymous content in text/plain format.
    #
    my $filename = $param_values {$filename_parameter} || $default_filename;

    # Now pull out only the safe variables.  Add our rest args too.
    my %safe_params = &Jarvis::Config::safe_variables ($jconfig, \%param_values, $rest_args_aref, 'p');

    # Add parameters to our command.  Die if any of the parameter names look dodgy.
    # This isn't a problem with datasets, since there we only look at parameters that
    # are coded into our SQL string.  But here we will take ALL parameters supplied
    # by the user, so we need to watch out for any funny business.
    foreach my $param (sort (keys %safe_params)) {
        # With the values we are more forgiving, but we quote them up hard in single
        # quotes for the shell.
        my $param_value = $safe_params{$param};
        &Jarvis::Error::debug ($jconfig, "Exec Parameter '$param' = '$param_value'");

        # MS Windows, we use double quotes.
        if ($^O eq "MSWin32") {
            $param_value = &escape_shell_windows ($param_value);
            $command .= " $param=\"$param_value\"";

        # These unix variants we use single quotes.
        } elsif (($^O eq "linux") || ($^O eq "solaris") || ($^O eq "darwin")) {
            $param_value = &escape_shell_unix ($param_value);
            $command .= " $param='$param_value'";

        # Not safe to continue.
        } else {
            die "Do not know how to escape Exec arguments for '$^O'.";
        }
    }

    # Set DEBUG if required.
    if ($jconfig->{'debug'}) {
        $ENV{'DEBUG'} = 1;
    }

    # Execute the command
    &Jarvis::Error::log ($jconfig, "Executing Command: $command");
    my $output =`$command`;

    # Failure?
    my $status = $?;
    if ($status != 0) {
        die "Command failed with status $status.\n$output";
    }

    # Are we supposed to add headers?  Does that include a filename header?
    # Note that if we really wanted to, we could squeeze in
    if ($add_headers) {
        my $mime_types = MIME::Types->new;
        my $mime_type = $mime_types->mimeTypeOf ($filename) || MIME::Types->type('text/plain');

        &Jarvis::Error::debug ($jconfig, "Exec returned mime type '" . $mime_type->type . "'");

        my $cookie = CGI::Cookie->new (-name => $jconfig->{'sname'}, -value => $jconfig->{'sid'});
        if ($filename) {
            print $jconfig->{'cgi'}->header(-type => $mime_type->type, 'Content-Disposition' => "inline; filename=$filename", -cookie => $cookie);

        } else {
            print $jconfig->{'cgi'}->header(-type => $mime_type->type, -cookie => $cookie);
        }
    }

    # Now print the output.  If the report didn't add headers like it was supposed
    # to, then this will all turn to custard.
    print $output;

    return 1;
}

1;