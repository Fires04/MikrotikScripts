# Mikrotik quality failover script 
# by David "Fires" Stein https://davidstein.cz


# configuration variables
# -----------------------
# link quiality variables
# bucketSize - maximal difference between successful pings and failed pings
# failThreshold - difference when connection is marked as failed
# recoveryThreshold - difference when connection is marked as recovered
# pingCount - ping count for every script run - DO NOT USE LESS THAN 3 IN FIRMWARE 7.0 - 7.6 - there is bug in Mikrotik firmware, reported to Mikrotik
# activeDistance - distance for active route
# disableDistance - distance for disabled routine

:local bucketSize 25 
:local failThreshold 15 
:local recoveryThreshold 5 
:local pingCount 3	
:local activeDistance 1 
:local disableDistance 10

# check and setup variables
:local primaryCheckIP 8.8.4.4
:local primaryRouteComment "primaryRoute"
:local secondaryRouteComment "secondaryRoute"


# DO NOT CHANGE THE SCRIPT UNDER THIS LINE
# "Never send a human to do a machine's job" – Agent Smith 
# ----------------------------------------

:global foSuccessfulPings
:global foTotalPings

:global foSwitchToPrimary
:global foSwitchToSecondary

:if ([:typeof $foSuccessfulPings] = "nothing") do={:set foSuccessfulPings $bucketSize}
:if ([:typeof $foTotalPings] = "nothing") do={:set foTotalPings $bucketSize}

:if ([:typeof $foSwitchToPrimary] = "nothing") do={:set foSwitchToPrimary 0}
:if ([:typeof $foSwitchToSecondary] = "nothing") do={:set foSwitchToSecondary 0}

# Basic requirements check
# ------------------------
:local priRoutesFind [:len [/ip/route find where comment=$primaryRouteComment]]
:local secRoutesFind [:len [/ip/route find where comment=$secondaryRouteComment]]

:if (($priRoutesFind != 1) or ($secRoutesFind != 1)) do={
	:put "FO ERROR - routes comments are not defined!"
	:log error "FO ERROR - routes comments are not defined!"
	:return "FO - ERROR"
}


# Link check routine
:put "------ FailOverScript-start ------"

# try ping via primaryRoute and calculate bucket
# ---------------------  

:local pingResult 
:set pingResult [ping $primaryCheckIP count=$pingCount]
:set foTotalPings ($foTotalPings + $pingCount)

:if ($pingResult >= $pingCount) do={
	:put "B - increasing succesfull rate"
	:set foSuccessfulPings ($foSuccessfulPings+($pingResult*2))
	:if ($foSuccessfulPings > $foTotalPings) do={
		:set foSuccessfulPings ($foTotalPings)
	}
} else={
	:if ($foSuccessfulPings < ($foTotalPings-$bucketSize)) do={
		:put "B - bucket size reached"
		:set foSuccessfulPings ($foTotalPings-$bucketSize)
	}
}

# check what routes are active
# -----------------------------
# primaryRoute = 0, secondaryRoute = 1
:local primRouteActive [:len [/ip/route find where comment=$primaryRouteComment distance=$activeDistance]]
:local activeRoute;
if ($primRouteActive = 1) do={
	:set activeRoute 0
} else={
	:set activeRoute 1
}
:put "D - active route $activeRoute"

# main switching logic
# ---------------------------
:local requiredRoute
:global foBucketDifference ($foTotalPings-$foSuccessfulPings)
:put "D - bucket difference $foBucketDifference"
# all good
:if (($foBucketDifference) <= $recoveryThreshold) do={
	:put "D - all good require primary route"
	:set requiredRoute 0
}
:if (($foBucketDifference > $recoveryThreshold) and ($foBucketDifference < $failThreshold) and $activeRoute=0 ) do={
	:put "D - primary is failing but still under limit"
	:set requiredRoute 0
}
:if ((($foBucketDifference) > $failThreshold)) do={
	:put "D - primary is bad - require secondary route"
	:set requiredRoute 1
}
:if (($foBucketDifference > $recoveryThreshold) and ($foBucketDifference < $failThreshold) and $activeRoute=1 ) do={
	:put "D - primary is recovering but still under limit"
	:set requiredRoute 1
}

:put "D - required route $requiredRoute"

# required actions after switching
# --------------------------
:if ($requiredRoute != $activeRoute) do={
	# is required to switch route
	:if ($requiredRoute = 0) do={
		:put "R - activating primary route"
		:ip/route/set distance=$activeDistance [/ip/route find where comment=$primaryRouteComment]
		:ip/route/set distance=$disableDistance [/ip/route find where comment=$secondaryRouteComment]
		:ip/firewall/connection remove [:ip/firewall/connection find]
	} else={
		:put "R - activating secondary route"
		:ip/route/set distance=$disableDistance [/ip/route find where comment=$primaryRouteComment]
		:ip/route/set distance=$activeDistance [/ip/route find where comment=$secondaryRouteComment]
		:ip/firewall/connection remove [:ip/firewall/connection find]
	}
}


:put "------ FailOverScript-end ------"
