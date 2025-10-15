# kis_build_system/modules/warning_summary.cmake
#
# Collects warnings during configuration and displays them at the end

# Initialize warning collection
set_property(GLOBAL PROPERTY KIS_BUILD_WARNINGS "")
set_property(GLOBAL PROPERTY KIS_BUILD_WARNINGS_COUNT 0)

#
# kis_collect_warning
#
# Adds a warning to the collection for end-of-configure summary
#
# Usage (simple):
#   kis_collect_warning("Package 'foo' uses deprecated DEFAULT variant")
#
# Usage (structured - for kis_message_warning_actionable):
#   kis_collect_warning("Title" "Message" "Hint")
#
function(kis_collect_warning)
    # Handle both simple and structured warnings
    if(ARGC EQUAL 1)
        # Simple warning message
        set(warning_text "${ARGV0}")
    elseif(ARGC EQUAL 3)
        # Structured warning (title, message, hint)
        set(warning_text "${ARGV0}: ${ARGV1} | Hint: ${ARGV2}")
    else()
        message(FATAL_ERROR "kis_collect_warning expects 1 or 3 arguments")
    endif()
    
    get_property(warnings GLOBAL PROPERTY KIS_BUILD_WARNINGS)
    list(APPEND warnings "${warning_text}")
    set_property(GLOBAL PROPERTY KIS_BUILD_WARNINGS "${warnings}")
    
    get_property(count GLOBAL PROPERTY KIS_BUILD_WARNINGS_COUNT)
    math(EXPR count "${count} + 1")
    set_property(GLOBAL PROPERTY KIS_BUILD_WARNINGS_COUNT ${count})
endfunction()

#
# kis_print_warning_summary
#
# Prints all collected warnings at the end of configuration
#
function(kis_print_warning_summary)
    get_property(warnings GLOBAL PROPERTY KIS_BUILD_WARNINGS)
    get_property(count GLOBAL PROPERTY KIS_BUILD_WARNINGS_COUNT)
    
    if(count GREATER 0)
        message(STATUS "")
        message(STATUS "╔═══════════════════════════════════════════════════════════════════════╗")
        message(STATUS "              [WARNING] Configuration Warnings (${count})")
        message(STATUS "╚═══════════════════════════════════════════════════════════════════════╝")
        message(STATUS "")
        
        set(warning_num 1)
        foreach(warning ${warnings})
            message(STATUS "  ${warning_num}. ${warning}")
            math(EXPR warning_num "${warning_num} + 1")
        endforeach()
        
        message(STATUS "")
        message(STATUS "┌──────────────────────────────────────────────────────────────────────┐")
        message(STATUS "│ [TIP] Address these warnings to ensure optimal build configuration   │")
        message(STATUS "└──────────────────────────────────────────────────────────────────────┘")
        message(STATUS "")
    else()
        kis_message_verbose("No configuration warnings")
    endif()
endfunction()
