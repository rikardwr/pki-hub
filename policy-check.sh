#!/bin/bash

LOG_FILE="/var/log/policy-check.log"
UPLOAD_DIR="/var/www/html/allowed-path"
CURL_BIN="/usr/bin/curl"
USER=${HTTP_X_REMOTE_USER}
REQUEST_PATH=${REQUEST_URI}

# Log initial details
{
    echo "Running policy-check.sh"
    echo "Request Method: ${REQUEST_METHOD}"
    echo "Request URI: ${REQUEST_URI}"
    echo "HTTP_X_REMOTE_USER: ${HTTP_X_REMOTE_USER}"
} >> ${LOG_FILE}

# Determine action based on the request method and URL path
case "${REQUEST_PATH}" in
    *approve*)
        ACTION="approve"
        ;;
    *load*)
        ACTION="load"
        ;;
    *)
        ACTION="read"
        ;;
esac

RESOURCE="plan"  # Resource is "plan"

# Log determined action and resource
{
    echo "Determined Action: ${ACTION}"
    echo "Determined Resource: ${RESOURCE}"
} >> ${LOG_FILE}

# Construct the payload for OPA
PAYLOAD="{\"input\": {\"user\": \"${USER}\", \"action\": \"${ACTION}\", \"resource\": \"${RESOURCE}\"}}"
echo "Constructed Payload: ${PAYLOAD}" >> ${LOG_FILE}

# Send the payload to the OPA server and get the response
RESPONSE=$(${CURL_BIN} -s -X POST http://localhost:8181/v1/data/authz/allow -d "${PAYLOAD}")
echo "OPA Response: ${RESPONSE}" >> ${LOG_FILE}

# Output headers for CGI script
echo "Content-type: text/html"
echo ""

# Check the response and decide the authorization
if [[ "${RESPONSE}" == *"true"* ]]; then
    echo "OPA Authorization: OK" >> ${LOG_FILE}
    
    # Handle file upload if method is POST or PUT and action is "load" or "approve"
    if [[ ("${REQUEST_METHOD}" == "POST" || "${REQUEST_METHOD}" == "PUT") && ("${ACTION}" == "load" || "${ACTION}" == "approve") ]]; then
        # Read the content length
        CONTENT_LENGTH=${CONTENT_LENGTH}
        echo "Content Length: ${CONTENT_LENGTH}" >> ${LOG_FILE}
        
        # Read the file content
        FILE_CONTENT=$(dd bs=1 count=${CONTENT_LENGTH} 2>/dev/null)

        # Extract the actual file content and signature from multipart form data
        FILE_CONTENT=$(echo "${FILE_CONTENT}" | awk '
            /Content-Disposition: form-data; name="file"/ {
                found_file = 1
                next
            }
            /Content-Disposition: form-data; name="signature"/ {
                found_sig = 1
                next
            }
            /Content-Type:/ {
                next
            }
            found_file {
                if ($0 ~ /^--/) {
                    found_file = 0
                    next
                }
                print > "/var/www/html/allowed-path/plan"
            }
            found_sig {
                if ($0 ~ /^--/) {
                    found_sig = 0
                    next
                }
                print > "/var/www/html/allowed-path/plan.sig"
            }
        ')

        echo "File Content: ${FILE_CONTENT}" >> ${LOG_FILE}
        
        echo "<html><body>OPA Authorization: OK and files uploaded</body></html>"
    else
        echo "<html><body>OPA Authorization: OK</body></html>"
    fi
    exit 0
else
    echo "<html><body>OPA Authorization: Forbidden</body></html>"
    echo "OPA Authorization: Forbidden" >> ${LOG_FILE}
    exit 1
fi
