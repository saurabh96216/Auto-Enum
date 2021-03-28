if [ $# -gt 1 ]; then
	echo "Usage: ./script.sh <domain>"
	echo "Example: ./script.sh yahoo.com" 
	exit 1
fi

#if [ $# -gt -1 ]; then
 #       echo "Usage: ./script.sh <domain>"
  #      echo "Example: ./script.sh yahoo.com" 
   #     exit 1
#fi

rm -rf dirscan third-levels *.txt results

WS="dirscan/";
if [ ! -d "$WS" ]; then
    mkdir $WS
fi

TD="third-levels/";
if [ ! -d "$TD" ]; then
    # If it doesn't create it
    mkdir $TD 
fi

RES="results/";
if [ ! -d "$RES" ]; then
    # If it doesn't create it
    mkdir $RES 
fi


echo "Gathering subdomains with Sublist3r..."

python3 ~/BugBounty/Tools/Sublist3r/sublist3r.py -d $1 -o subdomains.txt



if
	cat subdomains.txt | grep -Po "(\w+\.\w+\.\w+)$"
then
	echo "Compiling third-level subdomains..."
	cat subdomains.txt | grep -Po "(\w+\.\w+\.\w+)$" | sort -u > third-level-subdomains.txt 
	echo "Gathering fourth-level domains with Sublist3r..."
#	for domain in $(cat third-level-subdomains.txt); do python3 ~/BugBounty/Tools/Sublist3r/sublist3r.py -d $domain -o third-levels/$domain.txt ;done
	if [ $# -eq 2 ];
	then
        echo "Probing for alive third-levels with httprobe..."
        cat subdomains.txt | sort -u | grep -v $2 | httprobe -s -p https:443 | sed 's/https\?:\/\///' | tr -d ":443" > probed.txt
	else
        	echo "Probing for alive third-levels with httprobe..."
        	cat subdomains.txt | sort -u | httprobe -s -p https:443 | sed 's/https\?:\/\///'  | tr -d ":443" > probed.txt
	fi
else
	echo "No third-level domains found..."

		if [ $# -eq 2 ]; 
       		then
        	echo "Probing for alive domains with httprobe..."
        	cat subdomains.txt | sort -u | grep -v $2 | httprobe -s -p https:443 | sed 's/https\?:\/\///' | tr -d ":443" > probed.txt
        	else
                	echo "Probing for alive domains with httprobe..."
                	cat subdomains.txt | sort -u | httprobe -s -p https:443 | sed 's/https\?:\/\///'  | tr -d ":443" > probed.txt
        	fi
fi


echo "Cleaning some files"
cat third-levels/* | grep -Po "(\w+\.\w+\.\w+\.\w+)$"
rm -rf third-level-subdomains.txt third-levels/ 



echo "Running hakrawler to crawl links from live hosts"
awk '$0="https://"$0' probed.txt | sort -u  > spiderlinks.txt
awk '$0="http://"$0' probed.txt | sort -u  >> spiderlinks.txt
for hak in $(cat spiderlinks.txt); do hakrawler -all -url $hak >> dirscan/hakrawler.txt;done
cat dirscan/hakrawler.txt
echo "Done with the first hakrawler scan."

cat dirscan/hakrawler.txt >> spiderlinks2.txt
cat spiderlinks2.txt|  grep $1 | gf urls | sort -u | qsreplace -a | tr -d '*' >> spiderlinks.txt
rm spiderlinks2.txt
echo "Running Gospider for the first time on hakrawler links (If this takes a long time, the second one will be VERY long)"

gospider -S spiderlinks.txt >> spiderlinks2.txt

cat spiderlinks2.txt | grep $1 | gf urls | sort -u | tr -d '*' | qsreplace -a | >> spiderlinks.txt
rm spiderlinks2.txt



echo "Done with the first GoSpider scan!"
echo "Running Waybackmachine on all successfully probed domain names"
awk '$0="https://"$0' probed.txt| waybackurls | grep $1 | sort -u >> spiderlinks.txt
awk '$0="https://"$0' probed.txt | sort -u  >> spiderlinks.txt
echo "Waybackmachine search finished."

echo "Link crawling is now finished; find results in text file: spiderlinks.txt"
echo "Probing all found URL's with HTTPX for all CODE 200 results."
cat spiderlinks.txt | httpx -mc 200 > spiderlinks2.txt
cat spiderlinks2.txt > spiderlinks.txt
rm spiderlinks2.txt
#for webdir in $(cat spiderlinks.txt); do ffuf -w ~/BugBounty/Wordlists/common.txt -u $webdir/FUZZ -recursion -recursion-depth 3 -c -v -maxtime 60 >> dirscan/ffuf.txt;done
echo "Making neat exploitation links with gf and some awkawk3000.." 
for patt in $(cat patterns); do gf $patt spiderlinks.txt >> interestinglinks.txt ; done

awk '$0="https://"$0' probed.txt | sort -u >> interestinglinks.txt
awk '$0="http://"$0' probed.txt | sort -u  >> interestinglinks.txt


echo "Running XSS scans on links.."

cat interestinglinks.txt | dalfox pipe > results/xss-results.txt

echo "Running SQL Injections on links"
# DSSS is a little slow, I'll try something else
for sqli in $(cat interestinglinks.txt); do python3 ~/BugBounty/Tools/DSSS/dsss.py -u $sqli >> results/sqliresults.txt;done
#for sqli in $(cat injectionlinks.txt); do sqlmap -u $sqli --batch >> sqliresults.txt; done


echo "Cleaning up files..."
RES="results/";
if [ ! -d "$RES" ]; then
    mkdir $RES
fi

echo "Exploiting links with nuclei templates..."
nuclei -t nuclei-templates/ -l interestinglinks.txt -o results/nuclei-results.txt


echo "Scanning is done, please refer to results and other text files to see what I found..."
