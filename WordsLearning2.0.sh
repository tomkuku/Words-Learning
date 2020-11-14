#!/usr/local/bin/bash

MSSQL_PASS="Password123!"
MSSQL_US="sa"
readonly db_name="WordsLearning"
# selected_group=""
# declare -a all_words

function exec_mssql_query() {
  # $1 - is query
  readarray -t lines< <(mssql -u $MSSQL_US -p $MSSQL_PASS -q "$1")

  if [ ${#lines[@]} -eq 1 ] ; then
    echo "Check is mssql server enable."
    exit 0
  fi

  for ((i=2;i<${#lines[@]}-4;i++)) ; do
    echo "${lines[${i}]}"
  done
}

function exec_mssql_query_without_output() {
  mssql -u $MSSQL_US -p $MSSQL_PASS -q "$1"
}

function create_new_group() {
  local new_group_name
  echo "Enter new group name:"
  read new_group_name
  local helper=`exec_mssql_query_without_output "USE $db_name; CREATE TABLE $new_group_name (id SMALLINT PRIMARY KEY, word VARCHAR(50), trans VARCHAR(50), num_of_all_ans TINYINT, num_of_cor_ans TINYINT);"`
  echo "Created!"
  sleep 0.4
}

function show_menu() {
  if [ `mssql -u $MSSQL_US -p $MSSQL_PASS -q ".tables" | wc -l | awk '{print $1}'` -eq 1 ] ; then
    echo "Check is mssql server enable."
    exit 0
  fi

  local is_rep=1

  while [ $is_rep -eq 1 ]
  do
    clear
    local all_tables=`exec_mssql_query "USE $db_name; SELECT name AS 'Table Name' FROM sys.tables;"`

    if [ -z "$all_tables" ] ; then
      echo "You don't have any groups."
      create_new_group
    else
      local tables_cnt=`echo "$all_tables" | wc -l | awk '{print $1}'`
      let tables_cnt-=6

      readarray -t groups< <(echo "$all_tables")

      for ((i=0; i<${#groups[@]}+1; i++)) ; do
        if [ $i -eq 0 ] ; then
          echo "${i}) Create new group"
        else
          echo "${i}) ${groups[((i-1))]}"
        fi
      done

      read option

      if [ $option -eq 0 ] ;  then
        create_new_group
      elif [ $option -gt 0 ] && [ $option -le ${#groups[@]} ] ; then
        selected_group=`echo "${groups[((option-1))]}" | awk '{print $1}'`
        show_group "$selected_group"
      else
        echo "bad choice!"
      fi
    fi

  done
}

function show_group() {
  local is_rep=1

  while [ $is_rep -eq 1 ] ; do

  clear

  for line in "${words_pack[@]}" ; do
    local word=`echo "$line" | awk -F: '{print $2}'`
    local trans=`echo "$line" | awk -F: '{print $3}'`
    echo "$word - $trans"
  done

    echo -e "l) start learning"
    echo "a) add new word"
    echo "r) remove group"
    echo "b) back to menu"
    read option

    case "$option" in
      'a')
          add_new_word_to_group "$1"
        ;;
      'l')
        learn "$1";;
      'r')
        clear
        read -p "Are you sure? n - no  y - yes" opt

        if [ "$opt" = "y" ] ; then
          exec_mssql_query_without_output "USE ${db_name}; DROP TABLE ${selected_group};"
          return
        fi
        ;;
      'b')
        return
        ;;
    esac
    clear
  done
}

function add_new_word_to_group() {
  # $1 - selected group
  declare -a local ids=$(exec_mssql_query "USE ${db_name}; SELECT id FROM Cars;")
  echo "USE ${db_name};" > temp_file_sql_queries

  local is_rep=1

  while [ $is_rep -eq 1 ]; do
    clear
    echo "Enter word (e - end adding)"
    local word
    read word

    if [ "$word" = "e" ] ; then break; fi

    word=`echo "$word" | tr " " +`

    echo "Enter translation:"
    local trans
    read trans
    trans=`echo "$trans" | tr " " +`
    genered_id=$(genere_UUID "${ids[@]}")
    ids+=($genered_id)
    echo "INSERT INTO ${1} VALUES (${genered_id}, '${word}', '${trans}', 0, 0);" >> temp_file_sql_queries
  done

  cat temp_file_sql_queries
  local helper=`exec_mssql_query_without_output "$(cat temp_file_sql_queries)"`
  rm temp_file_sql_queries
}

function genere_UUID() {
  readarray -t used_ids< <(echo "$*")
  local uuid=""
  local is_rep=1

  while [ $is_rep -eq 1 ] ; do
    uuid=""
    is_rep=0
    for((i=0;i<3;i++)) ; do uuid+="$(( RANDOM % 9 ))" ; done

    for ((i=0;i<${#used_ids[@]};i++)) ; do
      if [ "$uuid" == "${used_ids[$i]}" ] ; then is_rep=1; fi
    done
  done

  echo "$uuid"
}

function get_all_words() {
  readarray -t lines< <(exec_mssql_query "USE $db_name; SELECT * FROM $1 ORDER BY num_of_cor_ans DESC;")

  declare -a words_packs

  for ((i=0;i<${#lines[@]};i++)); do
    line="${lines[${i}]}"
    if [ -z "$line" ] ; then continue; fi

    id=`echo "$line" | awk '{print $1}'`
    word=`echo "$line" | awk '{print $2}'`
    trans=`echo "$line" | awk '{print $3}'`
    num_of_all_ans=`echo "$line" | awk '{print $4}'`
    num_of_cor_ans=`echo "$line" | awk '{print $5}'`
    # let factor=num_of_all_ans-num_of_cor_ans
    echo "${id}:${word}:${trans}:${num_of_all_ans}:${num_of_cor_ans}"
  done
}

function learn() {
  # $1 - selected group
  readarray -t all_words< <(get_all_words "$1")
  local all_words_count=(${#all_words[@]})
  local remainder_of_five
  local rep_num

  echo "all_words_count $all_words_count"

  if [ $all_words_count -eq 0 ] ; then
    echo "You havn't added any words to this group!"
    return
  elif (( all_words_count <= 7 )) ; then
    rep_num=1
    let remainder_of_five=all_words_count%5
  else
    let remainder_of_five=all_words_count%5
    let rep_num=(all_words_count-remainder_of_five)/5
    # The remainder of modulo-five if is less then 3 is adding to last words queue. Otherwise a new queue is created.
    if [ $remainder_of_five -gt 2 ] ; then let rep_num++; fi
  fi

  echo "rep_num: $rep_num remainder_of_five: $remainder_of_five"

  declare -a words_to_asking_queue

  for ((i=0;i<rep_num;i++)) ; do
    let bottom_range=i*5
    local top_range

    if (( i == (rep_num-1) )) ; then # last queue
      if [ $remainder_of_five -gt 2 ] ; then
        if (( all_words_count > 5 )) ; then
          let top_range=bottom_range+remainder_of_five+3;
        else
          let top_range=bottom_range+remainder_of_five-1;
        fi
      else
        let top_range=bottom_range+remainder_of_five;
      fi
    else
      let top_range=bottom_range+4
    fi

    unset words_to_asking_queue
    for ((j=bottom_range;j<=top_range;j++)) ; do
      words_to_asking_queue+=("${all_words[$j]}")
    done

    # Showing
    clear
    echo "USE ${db_name}" > working_file
    echo "Try to remember:"
    for ((j=0;j<${#words_to_asking_queue[@]};j++)); do
      local current_word=${words_to_asking_queue[$j]}
      if [ $(echo "$current_word" | awk -F: '{print $4}') -gt 0 ] ; then continue; fi
      local id=`echo "$current_word" | awk -F: '{print $1}'`
      local word=`echo "$current_word" | awk -F: '{print $2}' | tr '+' ' '`
      local trans=`echo "$current_word" | awk -F: '{print $3}' | tr '+' ' '`
      echo "$word - $trans"
      read -p "Any key to next" next
      echo "UPDATE ${1} SET is_showed=1 WHERE id=${id};" >> working_file
    done

    helper=`exec_mssql_query_without_output "$(cat working_file)"`
    rm working_file

    # Asking
    declare -i learned_words_num=0

    for ((j=0;j<${#words_to_asking_queue[@]};j++)); do
      local current_word=${words_to_asking_queue[$j]}
      local id=`echo "$current_word" | awk -F: '{print $1}'`
      local word=`echo "$current_word" | awk -F: '{print $2}'`
      local trans=`echo "$current_word" | awk -F: '{print $3}'`
      local num_of_all_ans=`echo "$current_word" | awk -F: '{print $4}'`
      local num_of_cor_ans=`echo "$current_word" | awk -F: '{print $5}'`

      clear
      echo "Learned: $learned_words_num | Rest: $((${#all_words[@]}-$learned_words_num))"
      local temp_trans=`echo "$trans" | tr '+' ' '`
      echo -e "Enter translation: $temp_trans \n1) I've already learned it\ne) End learning"
      read  -p "-> " enterd_trans

      case "$(echo "$enterd_trans" | tr '[:upper:]' '[:lower:]')" in
        # Correct answer
        "$(echo "$word" | tr '[:upper:]' '[:lower:]' | tr '+' ' ')")
          echo "Good!"
          let num_of_all_ans+=1
          let num_of_cor_ans+=1
          sleep 0.3
          ;;
        '1')
          num_of_cor_ans=3
          echo "OK"
          sleep 0.3
          ;;
        'e')
          break ;;
        *)
          clear
          echo -e "Incorrect answer!\n"
          local temp_word=`echo "$word" | tr '+' ' '`
          echo -e "Correct answer: $temp_word \nYour answer:    $enterd_trans"
          echo -e "\n1) Accept my spelling\n2) Change translation of this word\nAny other key - next word"
          read option

          case "$option" in
            '1')
              let num_of_all_ans+=1
              let num_of_cor_ans+=1
              sleep 0.2
              ;;
            '2')
              clear
              read -p "Eneter new translation: " word
              word=`echo "$word" | tr '+' ' '`
              num_of_all_ans=0
              num_of_cor_ans=0
              echo "Changed"
              sleep 0.4
              ;;
            *)
              let num_of_all_ans+=1
              ;;
          esac
          ;;
      esac

      current_word=("${id}:${word}:${trans}:${num_of_all_ans}:${num_of_cor_ans}:1")

      # Check if current word is learned if not, word is adding to end of words_to_asking_queue to asking again.
      if (( num_of_cor_ans < 3 )) ; then
        words_to_asking_queue+=("$current_word")
      else
        let learned_words_num++
      fi

      # Change current word in all_words to resave in whole array
      for ((k=bottom_range;k<=top_range;k++)) ; do
        echo "k: $k - $(echo "${all_words[$k]}" | awk -F: '{print $1}')"
        if [ $(echo "${all_words[$k]}" | awk -F: '{print $1}') = "$id" ] ; then
          echo "found!"
          all_words[$k]="$current_word"
          break
        fi
      done

      echo "${all_words[@]}"

    done
  done

  # Save chagnes in database
  touch temp_file_sql_queries
  echo "USE ${db_name};" >> temp_file_sql_queries

  for ((i=0;i<${#all_words[@]};i++)) ; do
    local id=`echo "${all_words[$i]}" | awk -F: '{print $1}'`
    local word=`echo "${all_words[$i]}" | awk -F: '{print $2}'`
    # local trans=`echo "${all_words[$i]}" | awk -F: '{print $3}'`
    declare -i local num_of_all_ans=`echo "${all_words[$i]}" | awk -F: '{print $4}'`
    declare -i local num_of_cor_ans=`echo "${all_words[$i]}" | awk -F: '{print $5}'`
    echo "UPDATE ${1} SET word='${word}', num_of_all_ans=${num_of_all_ans}, num_of_cor_ans=${num_of_cor_ans} WHERE id=${id};" >> temp_file_sql_queries
  done

  exec_mssql_query_without_output "$(cat temp_file_sql_queries)"
  rm temp_file_sql_queries

  clear
  echo -e "You can all words!\nCongratulations!"
  sleep 4
}

show_menu

#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
