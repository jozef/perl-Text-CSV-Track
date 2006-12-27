
package Text::CSV::Track::Max;

our $VERSION = '1.0';
use 5.006;

use strict;
use warnings;

use base qw(Text::CSV::Track);

use FindBin;

use Text::CSV;
use Carp::Clan;


sub max_value_of {
	my $self          = shift;
	my $indetificator = shift;
	my $is_set = (@_ > 0 ? 1 : 0);	#get or set request depending on number of arguments
	my $value = shift;

	#check if we have identificator
	return if not $indetificator;

	#if get call super value_of
	return $self->value_of($indentificator) if not $is_set;
	
	
	#lazy initialization
	$self->_init();
			
	#set
	my $old_value = $self->value_of{$indetificator};
	if (not defined $value or ($old_value < $value)) {
		$self->value_of{$indetificator, $value};
	}
}
