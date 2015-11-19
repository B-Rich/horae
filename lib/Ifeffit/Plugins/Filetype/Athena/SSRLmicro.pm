package Ifeffit::Plugins::Filetype::Athena::SSRLmicro;  # -*- cperl -*-


=head1 NAME

Ifeffit::Plugin::Filetype::Athena::SSRL - SSRL XAFS Data Collector 1.3 ASCII filetype plugin

=head1 SYNOPSIS

This plugin directly reads the files written by Sam Webb's SSRL
MicroXAFS Data Collector 1.0.

=head1 SSRL files

This plugin comments out the header lines, constructs a column label
line out of the Data: section, moves the first column (real time
clock) to the second column, and strips out the ICR channels.

This was developed using a single example data file from the CLS HXMA
beamline.  Are other scalar channels ever saved to these files?  I do
not know.  If so, strange behavior might ensue.

=head1 AUTHOR

  Bruce Ravel <bravel@bnl.gov>
  http://cars9.uchicago.edu.edu/~ravel/software/exafs/
  Athena copyright (c) 2001-2008

=cut

use vars qw(@ISA @EXPORT @EXPORT_OK);
use Exporter;
use File::Basename;
use File::Copy;
@ISA = qw(Exporter AutoLoader);
@EXPORT_OK = qw();

use vars qw($is_binary $description);
$is_binary = 1;
$description = "Read files from the SSRL microXAFS Data Collector 1.0.";




sub is {
  shift;
  my $null = chr(0);
  my $data = shift;
  open D, $data or die "could not open $data as data (SSRL)\n";
  my $line = <D>;
  close D;
  my $is_ssrl  = ($line =~ m{^\s*SSRL\s+MicroEXAFS Data Collector});
  close D;
  return 1 if $is_ssrl;
  return 0;
};

sub fix {
  shift;
  my ($data, $stash_dir, $top, $r_hash) = @_;
  my ($nme, $pth, $suffix) = fileparse($data);
  my $new = File::Spec->catfile($stash_dir, $nme);
  ($new = File::Spec->catfile($stash_dir, "toss")) if (length($new) > 127);
  open D, $data or die "could not open $data as data (fix in SSRLA)\n";
  open N, ">".$new or die "could not write to $new (fix in SSRLA)\n";
  my @labels;
  my @offsets;
  my @detectors;
  my @scalars;
  my @icr;
  my ($header, $labels) = (1, 0);
  while (<D>) {
    chomp;
    if ($_ =~ /^\s*Data:/) {
      $header = 0;
      $labels++;
      next;
    };
    if (($_ =~ /^\s*$/) and $labels) { # labels end with a blank line, data follows
      (($header, $labels) = (0,0));
      ##         energy       RTC         I0
      @labels = ($labels[1], $labels[0], @labels[@detectors], @labels[@scalars]);
      print N "# ", "-"x30, $/;
      print N "# ", join(" ", @labels), $/;
      next;
    };
    if ($labels) {
      $labels++;
      my $this = $_;
      $this =~ s/\s+$//;
      $this =~ s/\s+/_/g;
      $this =~ s/\./_/g;
      push @labels, $this;
      next if (($this =~ m{time}i) or ($this =~ m{energy}i));
      push @scalars,   $labels-2 if ($this =~ m{SCA});
      push @icr,       $labels-2 if ($this =~ m{ICR});
      push @detectors, $labels-2 if ($this !~ m{(?:ICR|SCA)});;
    } elsif ($header) {		# comment header
      if ($_ =~ /^\s*Offsets/) {
	print N "# ", $_, $/;
	my $line = <D>;
	@offsets = split(" ", $line);
	@offsets = ($offsets[1], $offsets[0], @offsets[@detectors], @offsets[@scalars]);
	print N "# ", join(" ", @offsets), $/;
      } else {
	print N "# ", $_, $/;
      };
    } else {			# data columns
      my @line = split(" ", $_);
      @line = ($line[1], $line[0], @line[@detectors], @line[@scalars]);
      my $nn = $#line+1;
      my $pattern = "%.4f  " x $nn . $/;
      #@line = map{ $line[$_] - $offsets[$_] } (0 .. $#line);
      printf N $pattern, @line;
    };
  };
  close N;
  close D;
  return $new;
}


1;
__END__
