# kis_build_system/modules/build_profiling.cmake
#
# Tracks and reports build times for packages and overall build

# Initialize profiling data
set_property(GLOBAL PROPERTY KIS_PROFILE_ENABLED FALSE)
set_property(GLOBAL PROPERTY KIS_PROFILE_ENTRIES "")
set_property(GLOBAL PROPERTY KIS_PROFILE_START_TIME "")

#
# kis_profile_init
#
# Initializes build profiling if enabled
#
function(kis_profile_init)
    # Always clear stale profiling data from previous runs
    set_property(GLOBAL PROPERTY KIS_PROFILE_ENTRIES "")
    set_property(GLOBAL PROPERTY KIS_PROFILE_START_TIME "")
    
    if(KIS_PROFILE_BUILD)
        set_property(GLOBAL PROPERTY KIS_PROFILE_ENABLED TRUE)
        string(TIMESTAMP start_time "%s")
        set_property(GLOBAL PROPERTY KIS_PROFILE_START_TIME "${start_time}")
        message(STATUS "[PROFILE] Build profiling enabled")
    else()
        set_property(GLOBAL PROPERTY KIS_PROFILE_ENABLED FALSE)
    endif()
endfunction()

#
# kis_profile_begin
#
# Records the start time for a package or phase
#
# Usage:
#   kis_profile_begin("package_name" "phase")
#
function(kis_profile_begin name phase)
    get_property(enabled GLOBAL PROPERTY KIS_PROFILE_ENABLED)
    if(NOT enabled)
        return()
    endif()
    
    string(TIMESTAMP start_time "%s")
    set_property(GLOBAL PROPERTY "KIS_PROFILE_${name}_${phase}_START" "${start_time}")
endfunction()

#
# kis_profile_end
#
# Records the end time and calculates duration for a package or phase
#
# Usage:
#   kis_profile_end("package_name" "phase")
#
function(kis_profile_end name phase)
    get_property(enabled GLOBAL PROPERTY KIS_PROFILE_ENABLED)
    if(NOT enabled)
        return()
    endif()
    string(TIMESTAMP end_time "%s")
    
    get_property(start_time GLOBAL PROPERTY "KIS_PROFILE_${name}_${phase}_START")
    if(NOT start_time)
        return()
    endif()
    math(EXPR duration "${end_time} - ${start_time}")
    # Store the entry
    get_property(entries GLOBAL PROPERTY KIS_PROFILE_ENTRIES)
    list(APPEND entries "${name}|${phase}|${duration}")
    set_property(GLOBAL PROPERTY KIS_PROFILE_ENTRIES "${entries}")
    
endfunction()

#
# kis_profile_report
#
# Generates and displays a build time profiling report
#
function(kis_profile_report)
    get_property(enabled GLOBAL PROPERTY KIS_PROFILE_ENABLED)
    if(NOT enabled)
        return()
    endif()
    
    get_property(entries GLOBAL PROPERTY KIS_PROFILE_ENTRIES)
    get_property(overall_start GLOBAL PROPERTY KIS_PROFILE_START_TIME)
    
    if(NOT entries)
        message(STATUS "")
        message(STATUS "[PROFILE] No profiling data collected")
        return()
    endif()
    
    # Calculate total time
    string(TIMESTAMP overall_end "%s")
    math(EXPR total_time "${overall_end} - ${overall_start}")
    
    # Parse and sort entries
    set(package_times "")
    set(max_duration 0)
    
    foreach(entry ${entries})
        string(REPLACE "|" ";" entry_parts "${entry}")
        list(GET entry_parts 0 pkg_name)
        list(GET entry_parts 1 phase)
        list(GET entry_parts 2 duration)
        
        # Aggregate by package (sum all phases)
        set(found FALSE)
        set(new_package_times "")
        foreach(pkg_time ${package_times})
            string(REPLACE "|" ";" pkg_parts "${pkg_time}")
            list(GET pkg_parts 0 existing_name)
            list(GET pkg_parts 1 existing_duration)
            
            if(existing_name STREQUAL pkg_name)
                math(EXPR new_duration "${existing_duration} + ${duration}")
                list(APPEND new_package_times "${existing_name}|${new_duration}")
                set(found TRUE)
            else()
                list(APPEND new_package_times "${pkg_time}")
            endif()
        endforeach()
        
        if(NOT found)
            list(APPEND new_package_times "${pkg_name}|${duration}")
        endif()
        
        set(package_times ${new_package_times})
        # Track max for bar chart scaling
        if(duration GREATER max_duration)
            set(max_duration ${duration})
        endif()
    endforeach()

    set(max_duration 0)
    foreach(pkg_time ${package_times})
        string(REPLACE "|" ";" pkg_parts "${pkg_time}")
        list(GET pkg_parts 1 duration)
        if(duration GREATER max_duration)
            set(max_duration ${duration})
        endif()
        
    endforeach()
    
    # Sort by duration (descending) - simple selection sort
    list(LENGTH package_times num_packages)
    if(num_packages GREATER 1)
        set(sorted_times "")
        set(remaining_times ${package_times})
        
        # Repeatedly find and remove the maximum
        foreach(iter RANGE 1 ${num_packages})
            set(max_duration_found 0)
            set(max_item "")
            set(max_index -1)
            set(current_index 0)
            
            foreach(pkg_time ${remaining_times})
                string(REPLACE "|" ";" parts "${pkg_time}")
                list(GET parts 1 duration)
                
                if(duration GREATER max_duration_found)
                    set(max_duration_found ${duration})
                    set(max_item "${pkg_time}")
                    set(max_index ${current_index})
                endif()
                
                math(EXPR current_index "${current_index} + 1")
            endforeach()
            
            if(max_index GREATER -1)
                list(APPEND sorted_times "${max_item}")
                list(REMOVE_AT remaining_times ${max_index})
            endif()
        endforeach()
        
        set(package_times ${sorted_times})
    endif()
    
    # Display report
    message(STATUS "")
    message(STATUS "========================================================================")
    message(STATUS "                    Build Time Profile")
    message(STATUS "========================================================================")
    message(STATUS "")
    
    set(bar_width 40)
    foreach(pkg_time ${package_times})
        string(REPLACE "|" ";" pkg_parts "${pkg_time}")
        list(GET pkg_parts 0 pkg_name)
        list(GET pkg_parts 1 duration)
        
        # Format duration
        if(duration LESS 60)
            set(duration_str "${duration}s")
        else()
            math(EXPR minutes "${duration} / 60")
            math(EXPR seconds "${duration} % 60")
            set(duration_str "${minutes}m ${seconds}s")
        endif()
        
        # Calculate bar length (proportional to max)
        if(max_duration GREATER 0)
            math(EXPR bar_len "(${duration} * ${bar_width}) / ${max_duration}")
        else()
            set(bar_len 0)
        endif()
        
        # Create bar
        set(bar "")
        if(bar_len GREATER 0)
            foreach(i RANGE 1 ${bar_len})
                string(APPEND bar "#")
            endforeach()
        endif()
        
        # Format package name (pad to 25 chars)
        string(LENGTH "${pkg_name}" name_len)
        set(padded_name "${pkg_name}")
        if(name_len LESS 25)
            math(EXPR pad_needed "25 - ${name_len}")
            foreach(i RANGE 1 ${pad_needed})
                string(APPEND padded_name " ")
            endforeach()
        endif()
        
        # Format duration (pad to 10 chars)
        string(LENGTH "${duration_str}" dur_len)
        set(padded_dur "${duration_str}")
        if(dur_len LESS 10)
            math(EXPR pad_needed "10 - ${dur_len}")
            foreach(i RANGE 1 ${pad_needed})
                string(APPEND padded_dur " ")
            endforeach()
        endif()
        
        message(STATUS "  ${padded_name} ${padded_dur} ${bar}")
    endforeach()
    
    message(STATUS "")
    message(STATUS "------------------------------------------------------------------------")
    
    # Format total time
    if(total_time LESS 60)
        set(total_str "${total_time}s")
    else()
        math(EXPR minutes "${total_time} / 60")
        math(EXPR seconds "${total_time} % 60")
        set(total_str "${minutes}m ${seconds}s")
    endif()
    
    message(STATUS "  Total configure time: ${total_str}")
    message(STATUS "========================================================================")
    message(STATUS "")
    
    # Export to file for later analysis
    set(profile_file "${CMAKE_BINARY_DIR}/build_profile.txt")
    file(WRITE "${profile_file}" "Build Time Profile\n")
    file(APPEND "${profile_file}" "==================\n\n")
    file(APPEND "${profile_file}" "Package                   Duration\n")
    file(APPEND "${profile_file}" "----------------------------------------\n")
    
    foreach(pkg_time ${package_times})
        string(REPLACE "|" ";" pkg_parts "${pkg_time}")
        list(GET pkg_parts 0 pkg_name)
        list(GET pkg_parts 1 duration)
        
        if(duration LESS 60)
            set(duration_str "${duration}s")
        else()
            math(EXPR minutes "${duration} / 60")
            math(EXPR seconds "${duration} % 60")
            set(duration_str "${minutes}m ${seconds}s")
        endif()
        
        file(APPEND "${profile_file}" "${pkg_name}: ${duration_str}\n")
    endforeach()
    
    file(APPEND "${profile_file}" "\nTotal: ${total_str}\n")
    
    message(STATUS "[PROFILE] Report saved to: ${profile_file}")
endfunction()