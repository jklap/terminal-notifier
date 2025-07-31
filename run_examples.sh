#!/usr/bin/env bash


echo "Basic alert"
terminal-notifier \
    -message 'Basic alert' \
sleep 5

echo "Basic alert with title"
terminal-notifier \
    -title 'My Alert' \
    -message 'Basic alert with title' \
sleep 5

echo "Basic alert with subtitle"
terminal-notifier \
    -title 'My Alert' \
    -subtitle 'Subtitle' \
    -message 'Basic alert with subtitle'
sleep 5

echo "Basic alert with sound"
terminal-notifier \
    -message 'Basic alert with sound' \
    -sound default
sleep 5

echo "Basic alert with sound default"
terminal-notifier \
    -message 'Basic alert with sound default' \
    -sound
sleep 5

echo "Alert with image"
cp assets/logo.png ./logo.png
terminal-notifier \
    -message 'Alert with image' \
    -contentImage "file://$(pwd)/logo.png"
sleep 5

echo "Basic alert - wait"
terminal-notifier \
    -message 'Basic alert - wait' \
    -wait \
    -json
sleep 5

echo "Open URL"
terminal-notifier \
    -message 'Open URL' \
    -open 'https://www.google.com/finance/quote/AAPL:NASDAQ'
sleep 5

echo "Open App"
terminal-notifier \
    -message 'Open App' \
    -activate 'com.apple.Terminal'
sleep 5

echo "Run command"
terminal-notifier \
    -message 'Run command' \
    -execute 'date >> /tmp/notification-test.log'
sleep 5

echo "Reply"
terminal-notifier \
    -message 'Reply' \
    -reply \
    -json
sleep 5

echo "Reply with placeholder"
terminal-notifier \
    -message 'Reply with placeholder' \
    -reply 'Type your message here' \
    -json
sleep 5

echo "Timeout"
terminal-notifier \
    -title 'Timeout' \
    -message 'Reply with a message before it is too late' \
    -reply \
    -timeout 5 \
    -json
sleep 5

echo "Yes no action"
terminal-notifier \
    -message 'Yes, no action' \
    -actions Yes,No \
    -json
sleep 5

echo "Close label"
terminal-notifier \
    -message 'Has Close label' \
    -closeLabel "Refresh" \
    -json
sleep 5

echo "Actions with dropdown label"
terminal-notifier \
    -message 'Actions with dropdown label' \
    -actions Now,'Later today','Tomorrow' \
    -dropdownLabel 'When?' \
    -json
sleep 5

echo "Actions with close label"
terminal-notifier \
    -message 'Actions with close label' \
    -actions Yes,Maybe \
    -closeLabel No \
    -json
sleep 5

echo "List"
terminal-notifier \
    -list ALL
sleep 5

exit 0
