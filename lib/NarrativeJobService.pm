package NarrativeJobService;

use strict;
use warnings;

1;
our $VERSION = '1.0.0';


sub new {
	my ($class, %h) = @_;
	if (defined($h{'shocktoken'}) && $h{'shocktoken'} eq '') {
		$h{'shocktoken'} = undef;
	}
	my $self = {
		aweserverurl	=> $ENV{'AWE_SERVER_URL'} ,
		shockurl	=> $ENV{'SHOCK_SERVER_URL'},
		clientgroup	=> $ENV{'AWE_CLIENT_GROUP'},
		shocktoken	=> $h{'shocktoken'}
	};
	bless $self, $class;
	#$self->readConfig();
	return $self;
}


