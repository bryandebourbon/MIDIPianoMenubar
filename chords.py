import requests
from bs4 import BeautifulSoup
import json
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)

# Base URL of the site
base_url = "https://www.pianochord.org"

# Function to scrape key links from the main menu
def scrape_key_links():
    homepage_url = base_url
    logging.info(f"Scraping key links from {homepage_url}")
    try:
        response = requests.get(homepage_url)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to retrieve key links: {e}")
        return {}

    soup = BeautifulSoup(response.content, 'html.parser')
    
    # Extract links to each key from the menu
    key_links = {}
    menu = soup.find('div', id='menu')
    if menu:
        link_elements = menu.find_all('a')
        for link in link_elements:
            key_name = link.get_text(strip=True)
            key_link = link['href']
            if not key_link.startswith("http"):
                key_link = base_url + "/" + key_link
            key_links[key_name] = key_link
            logging.info(f"Found key link: {key_name} -> {key_link}")
    else:
        logging.warning("No 'menu' div found on the page.")

    return key_links

# Function to scrape chord categories and their links from a key page
def scrape_chord_categories(key_url):
    logging.info(f"Scraping chord categories from {key_url}")
    try:
        response = requests.get(key_url)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to retrieve chord categories: {e}")
        return {}

    soup = BeautifulSoup(response.content, 'html.parser')

    chords = {}
    # Find the section containing the chord category links
    chord_elements = soup.select('p a.in-line')
    logging.info(f"Found {len(chord_elements)} chord elements.")
    for chord in chord_elements:
        chord_name = chord.get_text(strip=True)
        chord_link = chord['href']
        if not chord_link.startswith("http"):
            chord_link = base_url + "/" + chord_link
        chords[chord_name] = chord_link
        logging.debug(f"Chord found: {chord_name} -> {chord_link}")

    return chords

# Function to scrape the notes from a chord detail page and format them correctly
def scrape_chord_notes(chord_url):
    logging.info(f"Scraping notes for chord from {chord_url}")
    try:
        response = requests.get(chord_url)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to retrieve chord notes: {e}")
        return []

    soup = BeautifulSoup(response.content, 'html.parser')

    chord_notes = []
    notes_span = soup.find('span', class_='notes')
    if notes_span:
        notes_text = notes_span.get_text(strip=True)
        logging.info(f"Extracted notes text: {notes_text}")
        if notes_text.startswith("Notes:"):
            notes = notes_text.replace("Notes:", "").strip().split(" - ")
            chord_notes = [note.strip() for note in notes]
            logging.debug(f"Formatted notes: {chord_notes}")
        else:
            logging.warning(f"Notes text format not as expected: {notes_text}")
    else:
        logging.warning("No notes span found on the page.")

    return chord_notes

# Main function to scrape data from the site
def main():
    # Scrape all key links from the homepage
    key_links = scrape_key_links()
    if not key_links:
        logging.error("No key links were found. Exiting the script.")
        return

    # Dictionary to hold chord names and their notes for all keys
    all_chords_to_notes_mapping = {}

    # Iterate through each key and its corresponding link
    for key_name, key_link in key_links.items():
        logging.info(f"Processing key: {key_name}")
        key_chords = scrape_chord_categories(key_link)
        if not key_chords:
            logging.warning(f"No chords found for {key_name}")
            continue

        # Dictionary to hold chord names and notes for this key
        chords_to_notes_mapping = {}

        # Iterate through each chord and get its notes
        for chord_name, chord_link in key_chords.items():
            logging.info(f"Processing chord: {chord_name}")
            chord_notes = scrape_chord_notes(chord_link)
            if chord_notes:
                chords_to_notes_mapping[chord_name] = chord_notes
                logging.info(f"Successfully added notes for {chord_name}: {chord_notes}")
            else:
                logging.warning(f"Failed to retrieve notes for {chord_name}")

        # Store this key's chords and notes in the main dictionary
        all_chords_to_notes_mapping[key_name] = chords_to_notes_mapping

    # Save the chord names and their notes for all keys to a JSON file
    output_file = "all_chords_notes.json"
    try:
        with open(output_file, "w") as file:
            json.dump(all_chords_to_notes_mapping, file, indent=4)
        logging.info(f"Chord notes for all keys have been successfully saved to '{output_file}'.")
    except Exception as e:
        logging.error(f"Failed to save chord notes to JSON file: {e}")

# Run the main function
if __name__ == "__main__":
    main()
