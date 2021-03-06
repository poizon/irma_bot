package Irma::Model::DB;

use strict;
use warnings;
use v5.10;
use utf8;

use App::Environ::Config;
use App::Environ::Mojo::Pg;
use Carp qw(croak);
use Cpanel::JSON::XS;
use Mojo::Log;
use Params::Validate qw(validate);

my %VALIDATION;

my @GROUP_FIELDS;

BEGIN {
  @GROUP_FIELDS = qw(
      greeting
      questions
      ban_url
      ban_question
  );

  %VALIDATION = (
    new => {
      logger => 1,
      pg     => 1,
    },
    read_group   => { id => 1, },
    create_group => { id => 1, ( map { ( $_ => 0 ) } @GROUP_FIELDS ) },
  );
}

use fields keys %{ $VALIDATION{new} };

use Class::XSAccessor { accessors => [ keys %{ $VALIDATION{new} } ] };

my $INSTANCE;

my $JSON = Cpanel::JSON::XS->new();

App::Environ::Config->register(
  qw(
      irma/migrations.yml
      )
);

sub instance {
  my $class = shift;

  unless ($INSTANCE) {
    my $logger = Mojo::Log->new;
    my $pg     = App::Environ::Mojo::Pg->pg('main');

    $pg->auto_migrate(1);

    $INSTANCE = $class->new( logger => $logger, pg => $pg );
  }

  return $INSTANCE;
}

sub new {
  my $class = shift;

  my %params = validate( @_, $VALIDATION{new} );

  my __PACKAGE__ $self = fields::new($class);

  foreach ( keys %{ $VALIDATION{new} } ) {
    $self->{$_} = $params{$_};
  }

  return $self;
}

sub read_group {
  my __PACKAGE__ $self = shift;

  my $cb = pop;
  croak 'No cb' unless $cb;

  my %params = validate( @_, $VALIDATION{read_group} );

  my $sql = q{
    SELECT greeting, questions, ban_url, ban_question
    FROM groups
    WHERE id = ?;
  };

  $self->_query(
    $sql,
    $params{id},
    sub {
      $self->_read_group_res( @_, $cb );
    }
  );

  return;
}

sub _read_group_res {
  my __PACKAGE__ $self = shift;
  my $cb = pop;
  my ( $db, $err, $res ) = @_;

  if ($err) {
    $cb->( undef, $err );
    return;
  }

  unless ( $res->rows ) {
    $cb->();
    return;
  }

  my $group = $res->hash;

  if ( $group->{questions} ) {
    $group->{questions} = $JSON->decode( $group->{questions} );
  }

  $cb->($group);

  return;
}

sub create_group {
  my __PACKAGE__ $self = shift;

  my $cb = pop;
  croak 'No cb' unless $cb;

  my %params = validate( @_, $VALIDATION{create_group} );

  my @args;
  my @vals;

  foreach my $field (@GROUP_FIELDS) {
    next unless exists $params{$field};

    if ( $field eq 'questions' ) {
      $params{$field} = $JSON->encode( $params{questions} );
    }

    push @args, $params{$field};
    push @vals, $field;
  }

  unless ( scalar @vals ) {
    $cb->();
    return;
  }

  my $vals_str = join ',', @vals;
  my $marks_str = join ',', ('?') x scalar(@vals);
  my $conflict_str = join ',', map {"EXCLUDED.$_"} @vals;

  my $sql = qq{
    INSERT INTO groups
    ( id, $vals_str ) VALUES ( ?, $marks_str )
    ON CONFLICT (id) DO UPDATE SET
      ($vals_str) = ($conflict_str)
  };

  $self->_query(
    $sql,
    $params{id},
    @args,
    sub {
      $self->_create_group_res( @_, $cb );
    }
  );

  return;
}

sub _create_group_res {
  my __PACKAGE__ $self = shift;
  my $cb = pop;
  my ( $db, $err, $res ) = @_;

  if ($err) {
    $cb->( undef, $err );
    return;
  }

  $cb->();

  return;
}

sub _query {
  my __PACKAGE__ $self = shift;
  my $cb = pop;

  $self->pg->db->query(
    @_,
    sub {
      $self->_query_res( @_, $cb );
    }
  );

  return;
}

sub _query_res {
  my __PACKAGE__ $self = shift;
  my $cb = pop;
  my ( $db, $err, $res ) = @_;

  if ($err) {
    $self->logger->error($err);
  }

  $cb->( $db, $err, $res );

  return;
}

1;
