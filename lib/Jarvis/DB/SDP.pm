##############################################################################
# Implements Jarvis::DB::SDP
#
# This class implements a pseudo database interaction with the SSAS 
# DataPump HTTP(S) service.
#
# This is invoked with
#  <database type="sdp" ... > 
#
# in the Jarvis application config file. 
##############################################################################
#
use strict;
use warnings;

package Jarvis::DB::SDP;

use MIME::Base64;
use SOAP::Lite;
use Data::Dumper;
use XML::Smart;

BEGIN {
    our @ISA = qw (Exporter);
    our @EXPORT = qw ();

    require Exporter;
}

##############################################################################
##############################################################################
# OBJECT LOADERS AND FINDERS
##############################################################################
##############################################################################

sub new {
    my ($class, $jconfig, $connect, $username, $password, $parameters) = @_;
   
    my $self = {};
    bless $self, $class;
    
    $self->init ($jconfig, $connect, $username, $password, $parameters);
    return $self;
}

sub init {
    my ($self, $jconfig, $connect, $username, $password, $parameters) = @_;
    
    $self->{'connect'} = $connect;
    $self->{'username'} = $username;
    $self->{'password'} = $password;
    $self->{'parameters'} = $parameters;

    # Create the client SOAP handle.
    my $soap = SOAP::Lite->new( proxy => $connect);
    
    $soap->readable(1);
    $soap->autotype(0);
    $soap->outputxml(1);
    $soap->default_ns('urn:schemas-microsoft-com:xml-analysis');
    $soap->transport->http_request->header ('Authorization' => 'Basic ' . MIME::Base64::encode("$username:$password"));
    $self->{'soap'} = $soap;    
}

##############################################################################
##############################################################################
# METHODS
##############################################################################
##############################################################################

# Dummy function.  We do not have a permanent connection.
sub disconnect {
}

################################################################################
# Makes the specified MDX request, and returns the XML object for another
# method to process.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $mdx - Query to execute
#
# Returns:
#       $root - XML object of successful response "root".
################################################################################
#
sub fetchall {
    
    my ($self, $jconfig, $mdx) = @_;
    
    &Jarvis::Error::debug ($jconfig, "Performing Execute request to SSAS DataPump.");
    
    my @property_list = ();
    if ($self->{'parameters'}->{'catalog'}) {
        push (@property_list,
            SOAP::Data->value(
                SOAP::Data->name('Catalog')->value($self->{'parameters'}->{'catalog'}),
            )
        );
    };
                    
    my $soap = $self->{'soap'};
    my $rxml = $soap->call('Execute',         
        SOAP::Data->name('Command')->value(
            \SOAP::Data->value(
                SOAP::Data->name('Statement')->value($mdx)
            )
        ),
        SOAP::Data->name('Properties')->value(
            \SOAP::Data->value(
                SOAP::Data->name('PropertyList')->value(
                    \@property_list
                )
            )
        )
    );
    
    # Check for errors.
    my $response = XML::Smart->new ($rxml) || die "Malformed XML on SDP response.";
    $response->{'soap:Envelope'}->{'soap:Body'} || die "No soap:Envelope/soap:Body found in SDP response.";
    
    if ($response->{'soap:Envelope'}->{'soap:Body'}->{'soap:Fault'}) {
        my $description = $response->{'soap:Envelope'}->{'soap:Body'}->{'soap:Fault'}->{'detail'}->{'Error'}->{'Description'}->content || 'SOAP Fault returned from SDP request.';
        my $error_code = $response->{'soap:Envelope'}->{'soap:Body'}->{'soap:Fault'}->{'detail'}->{'Error'}->{'ErrorCode'}->content || 'unknown';
        my $source = $response->{'soap:Envelope'}->{'soap:Body'}->{'soap:Fault'}->{'detail'}->{'Error'}->{'Source'}->content || 'SSAS DataPump';
        die "$source returned error $error_code: $description";
    }
    
    return $response->{'soap:Envelope'}->{'soap:Body'}->{'ExecuteResponse'}->{'return'}->{'root'} 
        || die "Missing ExecuteResponse/return/root in SDP response.";
}
    
################################################################################
# Makes the specified MDX request, and 
#
# This function only processes a single dataset.  The parent method may invoke
# us multiple times for a single request, and combine into a single return 
# object.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $mdx - Query to execute
#       $row_label - What name to use to store our row labels.
#
# Returns:
#       $rows_aref - Array of tuple data returned.
#       $column_names_aref - Array of tuple column names, if available.
################################################################################
#
sub fetchall_arrayref {
    my ($self, $jconfig, $mdx, $row_label) = @_;
    
    # Get the raw data.
    my $root = $self->fetchall ($jconfig, $mdx);
    
    &Jarvis::Error::debug ($jconfig, "Converting to Array of tuples.");

    # Now the fun bit.  Convert the deep complicated structure into 2D tuple array like DBI would.
    my @axis_names = map { $_->{'name'}->content } $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}('@');
    (scalar @axis_names == 3) || die "Require exactly two Axes for 2D tuple encoding.";

    # What are the names for the column/row axes?    
    my $column_axis_name = $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}[0]->{'HierarchyInfo'}->{'name'}->content || "Unknown Axis0 Name";
    my $row_axis_name = $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}[1]->{'HierarchyInfo'}->{'name'}->content || "Unknown Axis1 Name";
    &Jarvis::Error::debug ($jconfig, "Column Axis = $column_axis_name");
    &Jarvis::Error::debug ($jconfig, "Row Axis = $row_axis_name");
    
    # What are the tuple names?
    ($root->{'Axes'}->{'Axis'}[0]->{'name'}->content eq 'Axis0') || die "Inconsistent Axis0 Name";
    ($root->{'Axes'}->{'Axis'}[1]->{'name'}->content eq 'Axis1') || die "Inconsistent Axis0 Name";
    
    my @column_names = map { $_->{'Member'}->{'Caption'}->content } $root->{'Axes'}->{'Axis'}[0]->{'Tuples'}{'Tuple'}('@');
    my $num_columns = scalar @column_names;
    
    my @row_names = map { $_->{'Member'}->{'Caption'}->content } $root->{'Axes'}->{'Axis'}[1]->{'Tuples'}{'Tuple'}('@');
    my $num_rows = scalar @row_names;    
    
    # Pre-fill the rows.
    &Jarvis::Error::debug ($jconfig, "Have $num_columns columns, $num_rows rows.");
    my @rows = ();
    foreach my $i (0 .. ($num_rows - 1)) {
        if ($row_label) {
            push (@rows, {$row_label => $row_names[$i]});
            
        } else {
            push (@rows, '');
        }
    }
    
    # Now the cell data
    foreach my $cell ($root->{'CellData'}->{'Cell'}('@')) {
        my $ordinal = $cell->{'CellOrdinal'}->content;
        my $value = 1 * $cell->{'Value'}->content;
        my $column = $ordinal % $num_columns;
        my $row = ($ordinal - $column) / $num_columns;
        my $column_name = $column_names[$column];
        $rows[$row]->{$column_name} = $value; 
    }

    # Finally put the row label column at the start of the column list.
    if ($row_label) {
        @column_names = ($row_label, @column_names);
    }

    return (\@rows, \@column_names);
}

1;