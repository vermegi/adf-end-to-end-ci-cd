
# Add sudo support for non-root user
if [ "${USERNAME}" != "root" ] && [ "${EXISTING_NON_ROOT_USER}" != "${USERNAME}" ]; then
    echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME
    chmod 0440 /etc/sudoers.d/$USERNAME
    EXISTING_NON_ROOT_USER="${USERNAME}"
fi

# ** Shell customization section **
if [ "${USERNAME}" = "root" ]; then 
    user_rc_path="/root"
else
    user_rc_path="/home/${USERNAME}"
fi

# Restore user .bashrc defaults from skeleton file if it doesn't exist or is empty
if [ ! -f "${user_rc_path}/.bashrc" ] || [ ! -s "${user_rc_path}/.bashrc" ] ; then
    cp  /etc/skel/.bashrc "${user_rc_path}/.bashrc"
fi

# Restore user .profile defaults from skeleton file if it doesn't exist or is empty
if  [ ! -f "${user_rc_path}/.profile" ] || [ ! -s "${user_rc_path}/.profile" ] ; then
    cp  /etc/skel/.profile "${user_rc_path}/.profile"
fi

# .bashrc/.zshrc snippet
rc_snippet="$(cat << 'EOF'
if [ -z "${USER}" ]; then export USER=$(whoami); fi
if [[ "${PATH}" != *"$HOME/.local/bin"* ]]; then export PATH="${PATH}:$HOME/.local/bin"; fi
# Display optional first run image specific notice if configured and terminal is interactive
if [ -t 1 ] && [[ "${TERM_PROGRAM}" = "vscode" || "${TERM_PROGRAM}" = "codespaces" ]] && [ ! -f "$HOME/.config/vscode-dev-containers/first-run-notice-already-displayed" ]; then
    if [ -f "/usr/local/etc/vscode-dev-containers/first-run-notice.txt" ]; then
        cat "/usr/local/etc/vscode-dev-containers/first-run-notice.txt"
    elif [ -f "/workspaces/.codespaces/shared/first-run-notice.txt" ]; then
        cat "/workspaces/.codespaces/shared/first-run-notice.txt"
    fi
    mkdir -p "$HOME/.config/vscode-dev-containers"
    # Mark first run notice as displayed after 10s to avoid problems with fast terminal refreshes hiding it
    ((sleep 10s; touch "$HOME/.config/vscode-dev-containers/first-run-notice-already-displayed") &)
fi
# Set the default git editor if not already set
if [ -z "$(git config --get core.editor)" ] && [ -z "${GIT_EDITOR}" ]; then
    if  [ "${TERM_PROGRAM}" = "vscode" ]; then
        if [[ -n $(command -v code-insiders) &&  -z $(command -v code) ]]; then 
            export GIT_EDITOR="code-insiders --wait"
        else 
            export GIT_EDITOR="code --wait"
        fi
    fi
fi
EOF
)"

# code shim, it fallbacks to code-insiders if code is not available
cat << 'EOF' > /usr/local/bin/code
#!/bin/sh
get_in_path_except_current() {
    which -a "$1" | grep -A1 "$0" | grep -v "$0"
}
code="$(get_in_path_except_current code)"
if [ -n "$code" ]; then
    exec "$code" "$@"
elif [ "$(command -v code-insiders)" ]; then
    exec code-insiders "$@"
else
    echo "code or code-insiders is not installed" >&2
    exit 127
fi
EOF
chmod +x /usr/local/bin/code

# systemctl shim - tells people to use 'service' if systemd is not running
cat << 'EOF' > /usr/local/bin/systemctl
#!/bin/sh
set -e
if [ -d "/run/systemd/system" ]; then
    exec /bin/systemctl "$@"
else
    echo '\n"systemd" is not running in this container due to its overhead.\nUse the "service" command to start services instead. e.g.: \n\nservice --status-all'
fi
EOF
chmod +x /usr/local/bin/systemctl

# Codespaces bash and OMZ themes - partly inspired by https://github.com/ohmyzsh/ohmyzsh/blob/master/themes/robbyrussell.zsh-theme
codespaces_bash="$(cat \
<<'EOF'
# Codespaces bash prompt theme
__bash_prompt() {
    local userpart='`export XIT=$? \
        && [ ! -z "${GITHUB_USER}" ] && echo -n "\[\033[0;32m\]@${GITHUB_USER} " || echo -n "\[\033[0;32m\]\u " \
        && [ "$XIT" -ne "0" ] && echo -n "\[\033[1;31m\]➜" || echo -n "\[\033[0m\]➜"`'
    local gitbranch='`\
        if [ "$(git config --get codespaces-theme.hide-status 2>/dev/null)" != 1 ]; then \
            export BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null); \
            if [ "${BRANCH}" != "" ]; then \
                echo -n "\[\033[0;36m\](\[\033[1;31m\]${BRANCH}" \
                && if git ls-files --error-unmatch -m --directory --no-empty-directory -o --exclude-standard ":/*" > /dev/null 2>&1; then \
                        echo -n " \[\033[1;33m\]✗"; \
                fi \
                && echo -n "\[\033[0;36m\]) "; \
            fi; \
        fi`'
    local lightblue='\[\033[1;34m\]'
    local removecolor='\[\033[0m\]'
    PS1="${userpart} ${lightblue}\w ${gitbranch}${removecolor}\$ "
    unset -f __bash_prompt
}
__bash_prompt
EOF
)"

codespaces_zsh="$(cat \
<<'EOF'
# Codespaces zsh prompt theme
__zsh_prompt() {
    local prompt_username
    if [ ! -z "${GITHUB_USER}" ]; then 
        prompt_username="@${GITHUB_USER}"
    else
        prompt_username="%n"
    fi
    PROMPT="%{$fg[green]%}${prompt_username} %(?:%{$reset_color%}➜ :%{$fg_bold[red]%}➜ )" # User/exit code arrow
    PROMPT+='%{$fg_bold[blue]%}%(5~|%-1~/…/%3~|%4~)%{$reset_color%} ' # cwd
    PROMPT+='$([ "$(git config --get codespaces-theme.hide-status 2>/dev/null)" != 1 ] && git_prompt_info)' # Git status
    PROMPT+='%{$fg[white]%}$ %{$reset_color%}'
    unset -f __zsh_prompt
}
ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[cyan]%}(%{$fg_bold[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
ZSH_THEME_GIT_PROMPT_DIRTY=" %{$fg_bold[yellow]%}✗%{$fg_bold[cyan]%})"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg_bold[cyan]%})"
__zsh_prompt
EOF
)"

# Add RC snippet and custom bash prompt
if [ "${RC_SNIPPET_ALREADY_ADDED}" != "true" ]; then
    echo "${rc_snippet}" >> /etc/bash.bashrc
    echo "${codespaces_bash}" >> "${user_rc_path}/.bashrc"
    echo 'export PROMPT_DIRTRIM=4' >> "${user_rc_path}/.bashrc"
    if [ "${USERNAME}" != "root" ]; then
        echo "${codespaces_bash}" >> "/root/.bashrc"
        echo 'export PROMPT_DIRTRIM=4' >> "/root/.bashrc"
    fi
    chown ${USERNAME}:${group_name} "${user_rc_path}/.bashrc"
    RC_SNIPPET_ALREADY_ADDED="true"
fi

# Optionally install and configure zsh and Oh My Zsh!
if [ "${INSTALL_ZSH}" = "true" ]; then
    if ! type zsh > /dev/null 2>&1; then
        apt_get_update_if_needed
        apt-get install -y zsh
    fi
    if [ "${ZSH_ALREADY_INSTALLED}" != "true" ]; then
        echo "${rc_snippet}" >> /etc/zsh/zshrc
        ZSH_ALREADY_INSTALLED="true"
    fi

    # Adapted, simplified inline Oh My Zsh! install steps that adds, defaults to a codespaces theme.
    # See https://github.com/ohmyzsh/ohmyzsh/blob/master/tools/install.sh for official script.
    oh_my_install_dir="${user_rc_path}/.oh-my-zsh"
    if [ ! -d "${oh_my_install_dir}" ] && [ "${INSTALL_OH_MYS}" = "true" ]; then
        template_path="${oh_my_install_dir}/templates/zshrc.zsh-template"
        user_rc_file="${user_rc_path}/.zshrc"
        umask g-w,o-w
        mkdir -p ${oh_my_install_dir}
        git clone --depth=1 \
            -c core.eol=lf \
            -c core.autocrlf=false \
            -c fsck.zeroPaddedFilemode=ignore \
            -c fetch.fsck.zeroPaddedFilemode=ignore \
            -c receive.fsck.zeroPaddedFilemode=ignore \
            "https://github.com/ohmyzsh/ohmyzsh" "${oh_my_install_dir}" 2>&1
        echo -e "$(cat "${template_path}")\nDISABLE_AUTO_UPDATE=true\nDISABLE_UPDATE_PROMPT=true" > ${user_rc_file}
        sed -i -e 's/ZSH_THEME=.*/ZSH_THEME="codespaces"/g' ${user_rc_file}

        mkdir -p ${oh_my_install_dir}/custom/themes
        echo "${codespaces_zsh}" > "${oh_my_install_dir}/custom/themes/codespaces.zsh-theme"
        # Shrink git while still enabling updates
        cd "${oh_my_install_dir}"
        git repack -a -d -f --depth=1 --window=1
        # Copy to non-root user if one is specified
        if [ "${USERNAME}" != "root" ]; then
            cp -rf "${user_rc_file}" "${oh_my_install_dir}" /root
            chown -R ${USERNAME}:${group_name} "${user_rc_path}"
        fi
    fi
fi

# Persist image metadata info, script if meta.env found in same directory
meta_info_script="$(cat << 'EOF'
#!/bin/sh
. /usr/local/etc/vscode-dev-containers/meta.env
# Minimal output
if [ "$1" = "version" ] || [ "$1" = "image-version" ]; then
    echo "${VERSION}"
    exit 0
elif [ "$1" = "release" ]; then
    echo "${GIT_REPOSITORY_RELEASE}"
    exit 0
elif [ "$1" = "content" ] || [ "$1" = "content-url" ] || [ "$1" = "contents" ] || [ "$1" = "contents-url" ]; then
    echo "${CONTENTS_URL}"
    exit 0
fi
#Full output
echo
echo "Development container image information"
echo
if [ ! -z "${VERSION}" ]; then echo "- Image version: ${VERSION}"; fi
if [ ! -z "${DEFINITION_ID}" ]; then echo "- Definition ID: ${DEFINITION_ID}"; fi
if [ ! -z "${VARIANT}" ]; then echo "- Variant: ${VARIANT}"; fi
if [ ! -z "${GIT_REPOSITORY}" ]; then echo "- Source code repository: ${GIT_REPOSITORY}"; fi
if [ ! -z "${GIT_REPOSITORY_RELEASE}" ]; then echo "- Source code release/branch: ${GIT_REPOSITORY_RELEASE}"; fi
if [ ! -z "${BUILD_TIMESTAMP}" ]; then echo "- Timestamp: ${BUILD_TIMESTAMP}"; fi
if [ ! -z "${CONTENTS_URL}" ]; then echo && echo "More info: ${CONTENTS_URL}"; fi
echo
EOF
)"
if [ -f "${SCRIPT_DIR}/meta.env" ]; then
    mkdir -p /usr/local/etc/vscode-dev-containers/
    cp -f "${SCRIPT_DIR}/meta.env" /usr/local/etc/vscode-dev-containers/meta.env
    echo "${meta_info_script}" > /usr/local/bin/devcontainer-info
    chmod +x /usr/local/bin/devcontainer-info
fi

# Write marker file
mkdir -p "$(dirname "${MARKER_FILE}")"
echo -e "\
    PACKAGES_ALREADY_INSTALLED=${PACKAGES_ALREADY_INSTALLED}\n\
    LOCALE_ALREADY_SET=${LOCALE_ALREADY_SET}\n\
    EXISTING_NON_ROOT_USER=${EXISTING_NON_ROOT_USER}\n\
    RC_SNIPPET_ALREADY_ADDED=${RC_SNIPPET_ALREADY_ADDED}\n\
    ZSH_ALREADY_INSTALLED=${ZSH_ALREADY_INSTALLED}" > "${MARKER_FILE}"

echo "Done!"
