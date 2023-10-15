# Here is the procedure how to prepare a new Oolite Release

## Here are the things that should still be improved

- Automatic handling of version numbers
- distribute version number into other documents (see Version-bump.txt)
- LibreOffice documents shall be automatically converted into PDF to ensure the PDF version is current
- Prepare changelog and announcement messages for website and forum
- Prepare new downloads page for website
- Publish downloads and news pages to the website
- Publish announcement on the forum

## Here are the steps that need to be executed

- Tag the version to be released on the master branch, which shall automatically trigger the full release cycle

## Source
The procedure is based on based on http://aegidian.org/bb/viewtopic.php?p=289632#p289632:

[quote=another_commander post_id=289632 time=1686765671 user_id=1603]
Stable releases are manually generated. There is no official documentation, but I can show you the steps and tasks needed by using an example from the days of 1,84. The text below is the mail that had been sent to the devs mailing list of that time in order to make sure everyone was up to date with what was going to happen. This is probably the closest there is to "how to make a release" instructions. The text has been slightly edited to remove actual names of people and add the note about the changelog.

[quote]
OK, here is the proposed release plan, as promised a few posts earlier:

17/07:	Full freeze. Whatever revision is up on master branch at that time becomes 1.84. Please do not commit any changes to master past that date and until release is complete. I will create a new draft release on that date on github and communicate by mail the git revision which will be used for building 1.84 just to make sure that we are all on the same page.

18/07:	Build binaries for all platforms, Deployment + Test Release, 32 (where applicable) & 64 bit. Windows will have updater utility for conversion to test release. That would be desired also for the other ports, but it is not necessary if it involves too much work or if we are not confident of the result. The binaries should be uploaded to the draft release on github. If that release is not visible to people other than myself (not sure because I've never done it before), then please send me download links and I will retrieve them and upload them to the draft as required. Also we need to ensure that release changelog is complete and correct.

19/07: Expected date of release. We should aim to do it as early as we can. Some coordination will be needed. We will have to do the following on that day:
- Ensure that the draft release page has all the binaries uploaded and virus-scanned.
- Have an announcement prepared already for the forum. I will make sure to have that done and reviewed well before 17/07.
- Have a new Downloads page on oolite.space ready to go, with links already pointing to the github binaries and stating that 1.84 is now the latest and recommended release, with the actual date of release.
- When ready to launch, I will make the draft release public, generating the 1.84 tag at the time of release creation. The tag should hopefully be the same as the revision used for generating our binaries, which is why we should not commit anything to master after the 17th of July.
- Getafix will have to publish the new Downloads page immediately after the github release becomes public.
- As soon as this is done, I will post the release announcement on the forum.
- Getafix will have to adjust the What's New page on the site to remove the words "Upcoming", "soon to be released" etc. where 1.84 is mentioned. The link to the release announcement on the site needs to be added to the bottom of the What's New page as well. 

And then we sit back and start counting seconds until the first critical bug report.[/quote]

You will have to change version numbers before any of this, of course.  Instructions for version bumping are in the Doc folder of the source: https://github.com/OoliteProject/oolite/blob/master/Doc/Version-bump.txt

Oh, and the Oolite Reference Sheet will probably have to be updated as well to have any references to oolite.space replaced by oolite,space and include any new keyboard settings that might have been added between 1.90 and now.
[/quote]


