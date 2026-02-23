# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
#if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
#then
#    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
#fi
#export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions

PS1='\u@\h \w\n$ '
export PS1

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/SIU/bin:/usr/pgsql-15/bin
export PATH

alias cdaudit='cd /var/opt/SIU/audit'
alias cde='cd /etc/opt/SIU'
alias cdl='cd /var/opt/SIU/log'
alias cdo='cd /opt/SIU'
alias cdout='cd /var/opt/SIU/output'
alias cdp='cd /var/opt/SIU/$(hostname)'
alias cds='cd /var/opt/bits/App/scripts'
alias cdt='cd /tmp'
alias cdtrl='cd /var/opt/SIU/ctrl'
alias cdv='cd /var/opt/SIU'
alias ll='ls -l'
alias lla='ls -la'
