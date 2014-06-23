#!/usr/bin/perl
#
# Set image title and keywords from reverse geocoding of embedded location.
#

use strict;
use warnings;

use Data::Dumper;
use Geo::Coder::Google;
use Image::ExifTool qw(:Public);
use List::MoreUtils qw(any);

die "Usage: $0 IMAGE ...\n" unless 1 <= @ARGV;

my $geocoder = Geo::Coder::Google->new(apiver => 3,
		key => "AIzaSyDLKJEH4ajlnSJm4TdYvZWEFvFQpal0Rt0");

my @files = @ARGV;
our $written = 0;
our %location_cache;

foreach my $file (@files) {
	process_file($file);
}
print "$written images updated\n";



#
# Process a single input file.
#
sub process_file {
	my $file = shift;

	my $exiftool = new Image::ExifTool;
	$exiftool->ExtractInfo($file);
	my $latitude = $exiftool->GetValue("GPSLatitude", "ValueConv");
	my $longitude = $exiftool->GetValue("GPSLongitude", "ValueConv");

	if (not defined $latitude or not defined $longitude) {
		print "$file: no location data\n";
		return;
	}

	print "$file: $latitude,$longitude => ";

	my @location = get_geocode($latitude, $longitude);

	my @route_hi_priority;
	my @route_low_priority;
	my %keywords;

	foreach my $result (@location) {
		foreach my $component (@{$result->{"address_components"}}) {
			my @types = @{$component->{"types"}};
			my $name = $component->{"long_name"};

			next if any {$_ eq "bus_station"} @types;

			if (any {$_ eq "route"} @types) {
				push @route_hi_priority, $name;
				$keywords{$name} = 1;
			} elsif (any {$_ eq "locality"} @types) {
				push @route_low_priority, $name;
				$keywords{$name} = 1;
			} elsif (any {$_ eq "sublocality"} @types) {
				$keywords{$name} = 1;
			} elsif (any {$_ eq "transit_station"} @types) {
				push @route_hi_priority, $name;
				$keywords{$name} = 1;
			} elsif (any {$_ eq "neighborhood"} @types) {
				push @route_low_priority, $name;
				$keywords{$name} = 1;
			} elsif (any {$_ eq "premise"} @types) {
				push @route_low_priority, $name;
				$keywords{$name} = 1;
			} elsif (any {$_ eq "postal_code_prefix"} @types) {
				$keywords{$name} = 1;
			}
		}
	}

	my @route = (@route_hi_priority, @route_low_priority);
	my $title = $route[0];

	printf "\"%s\" [%s] ... ", $title, join(", ", sort keys %keywords);

	my $write = 0;
	my %file_keywords;

	foreach my $kw ($exiftool->GetValue("Subject", "ValueConv")) {
		$file_keywords{$kw} = 1;
	}
	foreach my $kw ($exiftool->GetValue("Keywords", "ValueConv")) {
		$file_keywords{$kw} = 1;
	}

	foreach my $kw (keys %keywords) {
		$write = 1 unless exists $file_keywords{$kw};
		$file_keywords{$kw} = 1;
	}

	my @write_keywords = sort keys %file_keywords;
	$exiftool->SetNewValue("Subject", \@write_keywords);
	$exiftool->SetNewValue("Keywords", \@write_keywords);

	if (defined $title) {
		my $title0 = $exiftool->GetValue("Title", "ValueConv") || "";
		my $obj0 = $exiftool->GetValue("ObjectName", "ValueConv") || "";
		if ($title ne $title0) {
			$exiftool->SetNewValue("Title", $title);
			$write = 1;
		}
		if ($title ne $obj0) {
			$exiftool->SetNewValue("ObjectName", $title);
			$write = 1;
		}
	}

	if ($write) {
		print "updated";
		$exiftool->WriteInfo($file);
		$written++;
	} else {
		print "unmodified";
	}

	print "\n";
}


#
# Determine the location for the given latitude and longitude.
#
sub get_geocode {
	my $latitude = shift;
	my $longitude = shift;
	my $latlng = "$latitude,$longitude";

	if (exists $location_cache{$latlng}) {
		print "(cached) ";
		return @{$location_cache{$latlng}};
	}

	my @location = $geocoder->reverse_geocode(latlng => $latlng);
	sleep 1;

	$location_cache{$latlng} = \@location;
	return @location;
}

