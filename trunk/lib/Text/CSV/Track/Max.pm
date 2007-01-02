=head1 NAME

Text::CSV::Track::Max - same as Text::CSV::Track but stores the greatest value

=head1 VERSION

v0.1 - created to track last login time

=head1 SYNOPSIS

	see Text::CSV::Track
	
=head1 DESCRIPTION

Only difference to Track is that before value is changed it is compared to the
old one. It it's higher then the value is updated if not old value persists.

=cut

package Text::CSV::Track::Max;

use version; our $VERSION = qv('0.2');
use 5.006;

use strict;
use warnings;

use base qw(Text::CSV::Track);

use FindBin;

use Text::CSV;
use Carp::Clan;


sub value_of {
	my $self          = shift;
	my $identificator = shift;
	my $is_set        = (@_ > 0 ? 1 : 0);	#get or set request depending on number of arguments
	my $value         = shift;

	#variables from self hash
	my $rh_value_of    = $self->{rh_value_of};

	#check if we have identificator
	return if not $identificator;

	#if get call super value_of
	return $self->SUPER::value_of($identificator) if not $is_set;
	
	#set
	my $old_value = $rh_value_of->{$identificator};	#don't call SUPER::value_of because it will active lazy init that is may be not necessary
	if (not defined $value
			or not defined $old_value
			or ($old_value < $value)
			
			) {		#if it is removel or the old value is smaller then set it
		$self->SUPER::value_of($identificator, $value);
	}
}
