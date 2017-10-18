%define smartmetroot /smartmet

Name:           smartmet-data-ecmwf
Version:        17.10.18
Release:        3%{?dist}.fmi
Summary:        SmartMet Data ECMWF
Group:          System Environment/Base
License:        MIT
URL:            https://github.com/fmidev/smartmet-data-ecmwf
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:	noarch

Requires:	smartmet-qdtools
Requires:	lbzip2


%description
TODO

%prep

%build

%pre

%install
rm -rf $RPM_BUILD_ROOT
mkdir $RPM_BUILD_ROOT
cd $RPM_BUILD_ROOT

mkdir -p .%{smartmetroot}/cnf/cron/{cron.d,cron.hourly}
mkdir -p .%{smartmetroot}/cnf/data
mkdir -p .%{smartmetroot}/tmp/data
mkdir -p .%{smartmetroot}/logs/data
mkdir -p .%{smartmetroot}/run/data/ecmwf/{bin,cnf}

cat > %{buildroot}%{smartmetroot}/cnf/cron/cron.d/ecmwf.cron <<EOF
# Run every hour to test if new data is available
# Script will wait new data for maximum of 50 minutes
00 * * * * /smartmet/run/data/ecmwf/bin/doecmwf.sh
EOF

cat > %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/clean_data_ecmwf <<EOF
#!/bin/sh
# Clean ECMWF data
cleaner -maxfiles 4 '_ecmwf_.*_surface.sqd' %{smartmetroot}/data/ecmwf
cleaner -maxfiles 4 '_ecmwf_.*_pressure.sqd' %{smartmetroot}/data/ecmwf
cleaner -maxfiles 4 '_ecmwf_.*_surface.sqd' %{smartmetroot}/editor/in
cleaner -maxfiles 4 '_ecmwf_.*_pressure.sqd' %{smartmetroot}/editor/in

# Clean incoming ECMWF data older than 1 day (1 * 24 * 60 = 1440 min)
find /smartmet/data/incoming/ecmwf -type f -mmin +1440 -delete
EOF

cat > %{buildroot}%{smartmetroot}/run/data/ecmwf/cnf/ecmwf-surface.st <<EOF
var x1 = par48 - AVGT(-1, -1, par48)
par48 = x1

var x2 = par50 - AVGT(-1, -1, par50)
par50 = x2

var x3 = par55 - AVGT(-1, -1, par55)
par55 = x3

var x4 = par264 - AVGT(-1, -1, par264)
par264 = x4

par354 = par50 / 3
EOF

cat > %{buildroot}%{smartmetroot}/cnf/data/ecmwf.cnf <<EOF
AREA="europe"
EOF

install -m 755 %_topdir/SOURCES/smartmet-data-ecmwf/doecmwf.sh %{buildroot}%{smartmetroot}/run/data/ecmwf/bin/
install -m 644 %_topdir/SOURCES/smartmet-data-ecmwf/ecmwf.conf %{buildroot}%{smartmetroot}/run/data/ecmwf/cnf/

%post

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,smartmet,smartmet,-)
%config(noreplace) %{smartmetroot}/cnf/data/ecmwf.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/ecmwf.cron
%config(noreplace) %{smartmetroot}/run/data/ecmwf/cnf/ecmwf.conf
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_ecmwf
%{smartmetroot}/*

%changelog
* Wed Oct 18 2017 Mikko Rauhala <mikko.rauhala@fmi.fi> 17.10.18-1.el7.fmi
- Initial version
