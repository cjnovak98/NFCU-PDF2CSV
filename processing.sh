#!/bin/bash
#podman run --pull=always --restart=unless-stopped -d -p 5006:5006 -v /mnt/share:/data:Z --name my_actual_budget actualbudget/actual-server:latest

pdf_dir=pdf_statements
pdf_cc_dir=pdf_statements/credit_card
txt_dir=converted_statements
txt_cc_dir=converted_statements/credit_card
acc_dir=processed_accounts
acc_cc_dir=processed_accounts/credit_card

#Make sure those dirs exist

function init {

if [[ -d $pdf_dir && -d $txt_dir && -d $acc_dir && -d $pdf_cc_dir && -d $txt_cc_dir && -d $acc_cc_dir ]]; then

    echo "Looks like you finally figured it out. Let's see what we can process!"

else

mkdir -p $pdf_dir $txt_dir $acc_dir $pdf_cc_dir $txt_cc_dir $acc_cc_dir

    echo "You need to create the directories first dummy... Let me create them for you, and you can try again."
    exit

fi

if find $pdf_dir -mindepth 1 -maxdepth 1 | read; then

    echo "Looks like you've got some files to process! Let's goooo"

else

    echo "I can't believe you did this.... You forgot to download the fucking statements too..."

fi


}


function pdf_to_text {

    echo -e "\n\nBeginning PDF to Text conversions. Entering PDF Directory now..."

    for file in $pdf_dir/*.pdf;do 

        echo "Found $file in $pdf_dir. Converting now... Done!"

        pdftotext -layout -eol unix $file


    done

    for file in $pdf_cc_dir/*.pdf;do 

        echo "Found $file in $pdf_cc_dir. Converting now... Done!"

        pdftotext -layout -eol unix $file


    done

    echo -e "\n\nAll PDF to Text conversions have been completed.\nMoving on to pulling account data out...\n\n"
    mv $pdf_dir/*.txt $txt_dir
    mv $pdf_cc_dir/*VISA*.txt $acc_cc_dir
}

#Data from server is put in /mnt/share

#Command used to extract data from PDF's:
#pdftotext -layout -eol unix 2024-04-12_STMSSCM.pdf

#grep -E '^[0-9]{2}-[0-9]{2}' 2024-04-12_STMSSCM.txt
#The above will take all of the transactions out of the file


#Take all processed accounts, turn them into a semicolon delimited CSV, and format them accordingly.
# cat processed_accounts/*.txt | grep -E '^[0-9]{2}-[0-9]{2}' |awk '{ gsub(/ {4,}/, ";"); print }' |sed 's/Ending Balance;/Ending Balance;;/g' |sed 's/Beginning Balance;/Beginning Balance;;/g' |awk -F';' '{print $4}'



function create_accounts {

echo -e "Bulk processing all converted files into account files...."

awk '
    # Initialize at the beginning of each new file
    FNR == 1 {
        account = 0;  # Reset account number for each file
        source_filename = FILENAME;  # Capture the original filename
        sub(/\.[^.]*$/, "", source_filename);  # Optionally strip the extension
        source_filename = source_filename "_account_";  # Prepare filename prefix
    }

    # Load lines into a circular buffer of size 11
    { a[NR%11] = $0; }

    # When "Beginning Balance" is found
    /Beginning Balance/ {
        account++;  # Increment account number
        filename = source_filename account ".txt";  # Append account number and extension
        for (i = NR-10; i <= NR; i++) {
            print a[i%11] > filename;  # Print to specific file
        }
        start = 1;  # Set flag to start printing subsequent lines
        next;
    }

    # Print all lines to current account file while flag is set
    start { print > filename; }

    # When "Ending Balance" is found
    /Ending Balance/ {
        print > filename;  # Print to specific file
        start = 0;  # Reset start flag
    }
' $txt_dir/*.txt


mv $txt_dir/*account*.txt $acc_dir

acc_file_num=$(ls -al $acc_dir |grep account |wc -l)

sleep 1
echo -e "\n\nWhew! That took a second. Looks like I processed $acc_file_num accounts!\nLet's start making that useful shall we?"


}

### Pull all payment/credits: ##### cat processed_accounts/credit_card/* |awk '/^PAYMENTS AND CREDITS/,/^TRANSACTIONS/' |grep -i Autozone -A8 -B8
### Pull only all transactions: ##### cat processed_accounts/credit_card/* |awk '/^PAYMENTS AND CREDITS/{p=1; next} /^TRANSACTIONS/{p=0} !p' 

function transform_accounts {

    for file in $acc_cc_dir/*.txt;do

        file_mem="$(cat $file)"
        account_number=$(echo "$file_mem" |grep 'ACCOUNT NUMBER' |grep -E 'xxxx xxxx xxxx [0-9]{4}$' |awk '{print $6}')
        echo "If I found a credit card. Here's the number: $account_number"
        ## awk '/^[0-9]{2}-[0-9]{2}/ {if (prev_date) print ""; prev_date=$1} {printf "%s ", $0} END {print ""}'
        processed_payments=$(echo "$file_mem" |grep 'xxxx xxxx xxxx' |grep -Ev '^[a-zA-Z]' |grep -v 'ACCOUNT NUMBER' |grep '\$'  |sed 's/^[[:space:]]*\([0-9]\)/\1/' |awk '{ gsub(/ {3,}/, ";"); print }' |awk -F';' '{print $1, $4, $NF}' OFS=';' |sed 's/\$//g' |sed 's/$/;'"$account_number"'/g' |grep -v ';.;')
            
        processed_transactions=$(echo "$file_mem" |awk '/^PAYMENTS AND CREDITS/{p=1; next} /^TRANSACTIONS/{p=0} !p' |grep '\$' |grep -E '[0-9]{2}/[0-9]{2}/[0-9]{2}' |sed "1 d" |grep -v "Due Date\|xxxx xxxx xxxx" |awk '{ gsub(/ {3,}/, ";"); print }' |sed 's/^;//g' |awk -F';' '{print $1, $4 $5, $NF}' OFS=';' |sed 's/\$/-/g' |sed 's/MOB PAYMENT RECEIVED;-/MOB PAYMENT RECEIVED;/g' |sed 's/$/;'"$account_number"'/g' |sed 's/^  //g')


    finished_cc_processing=$(echo -e "$processed_payments\n$processed_transactions\n$finished_cc_processing")

    done


    for file in $acc_dir/*.txt;do

        file_mem="$(cat $file |sed 's/\([0-9,]\+\)\.[0-9][0-9,] -/-\1.00/')"
        savings_account=$(echo "$file_mem" |head|grep Savings |grep -v ^Savings$)
        checking_account=$(echo "$file_mem" |head|grep Checking |grep -v ^Checking$)
        year=$(echo "$file" |sed 's/'$acc_dir'\///g' |awk -F'-' '{print $1}' OFS='-')

        echo "If I found an account it's listed here: $savings_account $checking_account The year is $year"

        if [[ $savings_account ]];then
            
            processed_file=$(echo "$file_mem" |sed 's/\([0-9,]\+\)\.[0-9][0-9,] -/-\1.00/' |sed 's/^ \+\([a-zA-Z]\)//g' |grep -v 'Page [0-9]\|ccess No. \|[0-9] - [0-9]' |sed 's/\([0-9,]\+\)\.[0-9][0-9,] -/-\1.00/' |sed 's/\f//g' |grep -v 'Checking -\|Savings -' |grep -E '[0-9]'|awk '/^[0-9]{2}-[0-9]{2}/ {if (prev_date) print ""; prev_date=$1} {printf "%s", $0} END {print ""}' | grep -E '^[0-9]{2}-[0-9]{2}'  |grep -v 'Page '|awk '{ gsub(/ {4,}/, ";"); print }' |sed 's/Ending Balance;/Ending Balance;0.00;/g' |sed 's/Beginning Balance;/Beginning Balance;0.00;/g' |sed 's/$/;'"$savings_account"'/g' |sed 's/^/'$year'-/g')

        fi

        if [[ $checking_account ]];then

            processed_file=$(echo "$file_mem" |sed 's/\([0-9,]\+\)\.[0-9][0-9,] -/-\1.00/' |sed 's/^ \+\([a-zA-Z]\)//g' |grep -v 'Page [0-9]\|ccess No. \|[0-9] - [0-9]' |sed 's/\([0-9,]\+\)\.[0-9][0-9,] -/-\1.00/' |sed 's/\f//g' |grep -E '[0-9]'|grep -v 'Checking -\|Savings -' |awk '/^[0-9]{2}-[0-9]{2}/ {if (prev_date) print ""; prev_date=$1} {printf "%s", $0} END {print ""}' | grep -E '^[0-9]{2}-[0-9]{2}'  |grep -v 'Page '|awk '{ gsub(/ {4,}/, ";"); print }' |sed 's/Ending Balance;/Ending Balance;0.00;/g' |sed 's/Beginning Balance;/Beginning Balance;0.00;/g' |sed 's/$/;'"$checking_account"'/g' |sed 's/^/'$year'-/g')

        fi

    finished_processing=$(echo -e "$processed_file\n$finished_processing")

    done

}


init

pdf_to_text

create_accounts

transform_accounts


echo "$finished_processing" |grep -Ev '^$' > all_accounts.csv
echo "$finished_cc_processing" |grep -Ev '^$' > all_cc_accounts.csv