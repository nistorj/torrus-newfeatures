#!/bin/sh
# 
# Periodically check if there are RRD files not updated by collector,
# and email the warning message.
# *.old.rrd files are ignored

# Stanislav Sinyagin <ssinyagin@k-open.com>
#

# Where the RRD files are located. Separate multiple paths with space
RRDSTORAGE=/srv/torrus/collector_rrd

# Maximum allowed age of an RRD file, in minutes.
MAXAGE=60

# Where to send complaints
NOTIFY=root

TMPFILE=/tmp/rrdup_notify.$$

cp /dev/null ${TMPFILE}

for d in ${RRDSTORAGE}; do
  find ${d} -name '*.rrd' ! -name '*.old.rrd' \
    -mmin +${MAXAGE} -print >>${TMPFILE}
done

nLines=`wc -l ${TMPFILE} | awk '{print $1}'`

if test ${nLines} -gt 0; then
  cat ${TMPFILE} | \
    mail -s "`printf \"Warning: %d aged RRD files\" ${nLines}`" ${NOTIFY}
fi

rm ${TMPFILE}

# Local Variables:
# mode: shell-script
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
